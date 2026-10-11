import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 特权辅助进程的调用结果。
enum HelperResultStatus {
  /// 命令执行成功。
  ok,

  /// 命令执行失败（如授权被取消、scxctl 报错）。
  failed,

  /// 辅助进程或目标工具不可用，调用方可以回退到其它实现。
  unavailable,
}

class HelperResult {
  const HelperResult(this.status, [this.message]);

  final HelperResultStatus status;
  final String? message;

  bool get isOk => status == HelperResultStatus.ok;

  static const ok = HelperResult(HelperResultStatus.ok);
}

/// 特权辅助进程启动失败。
class HelperStartException implements Exception {
  HelperStartException(this.message, {this.unavailable = false});

  final String message;

  /// 为 true 表示环境中缺少必要组件（如 pkexec/bash），调用方可回退。
  final bool unavailable;

  @override
  String toString() => message;
}

/// 常驻 root 辅助进程（经 pkexec 一次性授权）。
///
/// 设计目标：应用本次运行内第一次特权操作用户只授权一次，
/// 之后所有特权命令（写配置、systemctl、scxctl 调度切换）都通过
/// 该进程执行，不再弹窗；应用退出（stdin 关闭）后进程自动结束，
/// 下次打开应用重新授权。
///
/// 协议：每次请求发送一行，辅助进程回复一行。
///
/// - `PING`：回复 `OK`
/// - `SYSTEMCTL enable|disable scx_loader`：回复 `OK` / `ERR <message>`
/// - `WRITE <path> <base64>`：回复 `OK` / `ERR <message>`
/// - `SCXCTL <scxctl路径base64> <参数base64...>`：回复 `OK` /
///   `ERR <message>` / `UNAVAILABLE <message>`
/// - `QUIT`：回复 `OK` 并退出
class PrivilegedHelper {
  Process? _process;
  IOSink? _stdin;
  StreamIterator<String>? _lines;
  Directory? _scriptDir;
  Future<void>? _starting;
  Future<void> _queue = Future.value();

  /// 管理员会话状态变化回调（激活/失效）。
  void Function()? onActiveChanged;

  /// 管理员会话当前是否已授权可用。
  bool get isActive => _process != null;

  /// 发起一次请求前确保会话已激活；首次会弹出 pkexec 授权窗口。
  Future<void> ensureActive() => _enqueue(() => _ensureActive());

  /// 设置/取消 scx_loader 服务开机自启。
  Future<HelperResult> setServiceEnabled({required bool enabled}) =>
      _enqueue(() async {
        try {
          await _ensureActive();
        } on HelperStartException catch (error) {
          return _startFailure(error);
        }
        return _parse(
          await _request('SYSTEMCTL ${enabled ? 'enable' : 'disable'} scx_loader'),
        );
      });

  /// 以 root 写入 scx_loader 配置文件。
  Future<HelperResult> writeConfigFile({
    required String path,
    required String content,
  }) => _enqueue(() async {
    try {
      await _ensureActive();
    } on HelperStartException catch (error) {
      return _startFailure(error);
    }
    final data = base64.encode(utf8.encode(content));
    return _parse(await _request('WRITE $path $data'));
  });

  /// 以 root 调用 scxctl（仍通过 scx_loader 守护进程控制调度器）。
  Future<HelperResult> runScxctl({
    required String executable,
    required List<String> arguments,
  }) => _enqueue(() async {
    try {
      await _ensureActive();
    } on HelperStartException catch (error) {
      return _startFailure(error);
    }
    final encoded = [
      base64.encode(utf8.encode(executable)),
      for (final argument in arguments) base64.encode(utf8.encode(argument)),
    ].join(' ');
    return _parse(await _request('SCXCTL $encoded'));
  });

  /// 结束管理员会话（应用退出时调用）。
  Future<void> stop() async {
    final stdin = _stdin;
    if (stdin != null) {
      try {
        stdin.writeln('QUIT');
        await stdin.flush();
      } catch (_) {
        // 进程可能已退出，忽略。
      }
    }
    _process?.kill();
    _reset();
  }

  // ---------------------------------------------------------------------------
  // 内部实现
  // ---------------------------------------------------------------------------

  /// 串行化所有请求，避免多个操作交叉读写管道。
  Future<T> _enqueue<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _ensureActive() {
    if (_process != null) {
      return Future.value();
    }
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    final bash = _findBash();
    if (bash == null) {
      throw HelperStartException('未找到 bash，无法启动管理员会话', unavailable: true);
    }

    final scriptDir = await Directory.systemTemp.createTemp('fl_scx_helper_');
    _scriptDir = scriptDir;
    final script = File('${scriptDir.path}/helper.sh');
    await script.writeAsString(_scriptSource, flush: true);

    Process process;
    try {
      process = await Process.start('pkexec', [bash, script.path]);
    } on ProcessException catch (error) {
      throw HelperStartException(
        '无法执行 pkexec：${error.message}',
        unavailable: true,
      );
    }

    final stderrBuffer = StringBuffer();
    process.stderr
        .transform(utf8.decoder)
        .listen((chunk) {
          if (stderrBuffer.length < 2000) {
            stderrBuffer.write(chunk);
          }
        })
        .onError((_) {});

    final lines = StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );

    bool ready;
    try {
      ready = await lines.moveNext().timeout(const Duration(seconds: 120));
    } on TimeoutException {
      process.kill();
      throw HelperStartException('管理员会话启动超时');
    }

    if (!ready || lines.current != 'READY') {
      throw await _describeStartFailure(process, stderrBuffer);
    }

    _process = process;
    _stdin = process.stdin;
    _lines = lines;
    unawaited(process.exitCode.then((_) => _handleExit(process)));
    onActiveChanged?.call();
  }

  /// 将 pkexec 的退出码转换为用户可读的启动失败异常。
  Future<HelperStartException> _describeStartFailure(
    Process process,
    StringBuffer stderrBuffer,
  ) async {
    int code;
    try {
      code = await process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process.kill();
      code = -1;
    }
    final stderr = stderrBuffer.toString().trim();
    switch (code) {
      case 126:
        return HelperStartException('授权被取消，操作未执行');
      case 127:
        // pkexec 无法执行（策略限制或环境问题）：标记为可回退，
        // 调度器控制可改用 D-Bus + polkit 交互授权。
        return HelperStartException(
          '未获得授权，操作未执行${stderr.isEmpty ? '' : '：$stderr'}',
          unavailable: true,
        );
      case -1:
        return HelperStartException('管理员会话启动超时');
      default:
        return HelperStartException(
          '管理员会话启动失败（退出码 $code）${stderr.isEmpty ? '' : '：$stderr'}',
        );
    }
  }

  Future<String> _request(String command) async {
    final stdin = _stdin;
    final lines = _lines;
    if (stdin == null || lines == null) {
      throw HelperStartException('管理员会话未启动', unavailable: true);
    }
    try {
      stdin.writeln(command);
      await stdin.flush();
      if (!await lines.moveNext().timeout(const Duration(seconds: 30))) {
        _reset();
        throw HelperStartException('管理员会话已结束，下次操作将重新授权');
      }
      return lines.current;
    } on TimeoutException {
      _process?.kill();
      _reset();
      throw HelperStartException('管理员会话响应超时');
    } on IOException catch (error) {
      _reset();
      throw HelperStartException('与管理员会话通信失败：$error');
    }
  }

  HelperResult _parse(String response) {
    if (response == 'OK') {
      return HelperResult.ok;
    }
    if (response.startsWith('ERR ')) {
      return HelperResult(HelperResultStatus.failed, response.substring(4));
    }
    if (response.startsWith('UNAVAILABLE ')) {
      return HelperResult(HelperResultStatus.unavailable, response.substring(12));
    }
    return HelperResult(HelperResultStatus.failed, '未知响应：$response');
  }

  HelperResult _startFailure(HelperStartException error) => HelperResult(
    error.unavailable
        ? HelperResultStatus.unavailable
        : HelperResultStatus.failed,
    error.message,
  );

  void _handleExit(Process process) {
    if (!identical(_process, process)) {
      return;
    }
    _reset();
  }

  void _reset() {
    _process = null;
    _stdin = null;
    _lines = null;
    final dir = _scriptDir;
    _scriptDir = null;
    if (dir != null) {
      unawaited(
        dir.delete(recursive: true).catchError((_) => dir),
      );
    }
    onActiveChanged?.call();
  }

  String? _findBash() {
    for (final path in const ['/usr/bin/bash', '/bin/bash']) {
      if (File(path).existsSync()) {
        return path;
      }
    }
    return null;
  }

  /// 以 root 运行的辅助脚本；仅接受白名单内的受限命令。
  static const _scriptSource = r'''
#!/usr/bin/bash
# fl_scx 特权辅助进程：由 pkexec 以 root 身份运行，经标准输入接收受限命令。
# 白名单：systemctl enable/disable scx_loader、scx_loader 配置文件写入、scxctl 调用。
B64=/usr/bin/base64
SYSTEMCTL=/usr/bin/systemctl

emit_ok() { printf 'OK\n'; }
emit_err() {
  local msg="$*"
  msg=${msg//$'\n'/ }
  printf 'ERR %s\n' "$msg"
}

printf 'READY\n'

while IFS= read -r line; do
  cmd=${line%% *}
  rest=${line#"$cmd"}
  rest=${rest#" "}
  case "$cmd" in
    PING) emit_ok ;;
    QUIT) emit_ok; exit 0 ;;
    SYSTEMCTL)
      action=${rest%% *}
      unit=${rest#* }
      case "$action:$unit" in
        enable:scx_loader|disable:scx_loader)
          if "$SYSTEMCTL" "$action" "$unit" >/dev/null 2>&1; then
            emit_ok
          else
            emit_err "systemctl $action $unit 失败"
          fi
          ;;
        *) emit_err 'systemctl 参数不允许' ;;
      esac
      ;;
    WRITE)
      path=${rest%% *}
      data=${rest#* }
      case "$path" in
        /etc/scx_loader/config.toml|/etc/scx_loader.toml|/usr/share/scx_loader/config.toml|/usr/share/scx_loader.toml) ;;
        *) emit_err '写入路径不允许'; continue ;;
      esac
      tmp="${path}.fl_scx.tmp"
      if printf '%s' "$data" | "$B64" -d > "$tmp" 2>/dev/null; then
        if mv -f "$tmp" "$path"; then
          emit_ok
        else
          rm -f "$tmp"
          emit_err '写入文件失败'
        fi
      else
        rm -f "$tmp"
        emit_err '配置数据解码失败'
      fi
      ;;
    SCXCTL)
      read -r -a tokens <<< "$rest"
      argv=()
      for token in "${tokens[@]}"; do
        decoded=$(printf '%s' "$token" | "$B64" -d 2>/dev/null) || { emit_err '参数解码失败'; continue 2; }
        argv+=("$decoded")
      done
      prog=${argv[0]:-}
      case "$prog" in
        */scxctl) ;;
        *) emit_err 'scxctl 路径不允许'; continue ;;
      esac
      if [ ! -x "$prog" ]; then
        printf 'UNAVAILABLE %s\n' 'scxctl 不可用'
        continue
      fi
      output=$("$prog" "${argv[@]:1}" 2>&1)
      code=$?
      if [ "$code" -eq 0 ]; then
        emit_ok
      else
        if [ -z "$output" ]; then output="scxctl 退出码 $code"; fi
        emit_err "$output"
      fi
      ;;
    *) emit_err '未知命令' ;;
  esac
done
''';
}
