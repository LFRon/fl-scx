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

/// 仅按 `\n` 断行的协议流转换器（去掉行尾 `\r`）。
///
/// 不能用 Dart 的 [LineSplitter]：它额外按 `\r` 断行，而 dpkg 的进度
/// 输出（`(正在读取数据库 … 5%\r…`）会被拆成多段，不带 `LOG ` 前缀的
/// 碎片会被误判为命令响应，导致安装中途报“未知响应”而误判失败。
class ProtocolLineSplitter extends StreamTransformerBase<String, String> {
  const ProtocolLineSplitter();

  @override
  Stream<String> bind(Stream<String> stream) async* {
    var buffer = '';
    await for (final chunk in stream) {
      buffer += chunk;
      var index = buffer.indexOf('\n');
      while (index != -1) {
        yield _stripCr(buffer.substring(0, index));
        buffer = buffer.substring(index + 1);
        index = buffer.indexOf('\n');
      }
    }
    if (buffer.isNotEmpty) {
      yield _stripCr(buffer);
    }
  }

  static String _stripCr(String line) =>
      line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
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
/// 之后所有特权命令（写配置、systemctl、scxctl 调度切换、apt 与
/// cargo 安装）都通过该进程执行，不再弹窗；应用退出（stdin 关闭）
/// 后进程自动结束，下次打开应用重新授权。
///
/// 协议：每次请求发送一行，辅助进程回复一行。
///
/// - `PING`：回复 `OK`
/// - `SYSTEMCTL daemon-reload|enable|disable scx_loader`：回复
///   `OK` / `ERR <message>`
/// - `WRITE <path> <base64>`：回复 `OK` / `ERR <message>`
/// - `SCXCTL <scxctl路径base64> <参数base64...>`：回复 `OK` /
///   `ERR <message>` / `UNAVAILABLE <message>`
/// - `APT update` / `APT install <包名...>`：回复 `OK` / `ERR <message>`
/// - `RUSTC_VERSION`：回复 `OK <rustc --version 输出>` / `ERR <message>`
/// - `RUSTUP_INSTALL`：经国内镜像（rsproxy.cn）安装 Rust 工具链
/// - `CARGO_INSTALL_LOADER` / `CARGO_INSTALL_LAVD`：crates.io 编译安装
/// - `QUIT`：回复 `OK` 并退出
///
/// 安装类命令执行期间，命令输出会逐行以 `LOG <文本>` 发送，直到最终
/// `OK` / `ERR <message>`；调用方通过 `onLog` 接收（用于安装日志对话框）。
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
      _run('SYSTEMCTL ${enabled ? 'enable' : 'disable'} scx_loader');

  /// 刷新 systemd 单元缓存（写入新的 unit 文件后）。
  Future<HelperResult> daemonReload() => _run('SYSTEMCTL daemon-reload');

  /// 以 root 写入 scx_loader 配置或系统集成文件（白名单路径）。
  Future<HelperResult> writeConfigFile({
    required String path,
    required String content,
  }) {
    final data = base64.encode(utf8.encode(content));
    return _run('WRITE $path $data');
  }

  /// 以 root 调用 scxctl（仍通过 scx_loader 守护进程控制调度器）。
  Future<HelperResult> runScxctl({
    required String executable,
    required List<String> arguments,
  }) {
    final encoded = [
      base64.encode(utf8.encode(executable)),
      for (final argument in arguments) base64.encode(utf8.encode(argument)),
    ].join(' ');
    return _run('SCXCTL $encoded');
  }

  /// 以 root 更新 apt 软件源；命令输出通过 [onLog] 逐行回传。
  Future<HelperResult> aptUpdate({void Function(String)? onLog}) =>
      _run('APT update', timeout: _aptTimeout, onLog: onLog);

  /// 以 root 安装白名单内的软件包（scx-scheds / scx-loader）；
  /// 命令输出通过 [onLog] 逐行回传。
  Future<HelperResult> aptInstall({
    required List<String> packages,
    void Function(String)? onLog,
  }) => _run(
    'APT install ${packages.join(' ')}',
    timeout: _aptTimeout,
    onLog: onLog,
  );

  /// 以 root 读取 rustc 版本（用于判断是否需要安装 Rust 工具链）。
  Future<HelperResult> rustcVersion() => _run('RUSTC_VERSION');

  /// 以 root 通过国内镜像（rsproxy.cn）安装/更新 Rust 工具链；
  /// 命令输出通过 [onLog] 逐行回传。
  Future<HelperResult> installRustToolchain({void Function(String)? onLog}) =>
      _run('RUSTUP_INSTALL', timeout: _installTimeout, onLog: onLog);

  /// 以 root 编译安装 scx_loader 与 scxctl 到 /usr/bin（crates.io）；
  /// 命令输出通过 [onLog] 逐行回传。
  Future<HelperResult> cargoInstallScxLoader({void Function(String)? onLog}) =>
      _run('CARGO_INSTALL_LOADER', timeout: _installTimeout, onLog: onLog);

  /// 以 root 编译安装 scx_lavd 调度器到 /usr/bin（crates.io）；
  /// 命令输出通过 [onLog] 逐行回传。
  Future<HelperResult> cargoInstallScxLavd({void Function(String)? onLog}) =>
      _run('CARGO_INSTALL_LAVD', timeout: _installTimeout, onLog: onLog);

  /// 编译安装类命令的等待上限（单次执行、不重试）。
  static const _installTimeout = Duration(minutes: 60);

  /// apt 类命令的等待上限。
  static const _aptTimeout = Duration(minutes: 30);

  /// 串行执行一条受限命令（必要时先激活管理员会话）。
  Future<HelperResult> _run(
    String command, {
    Duration timeout = const Duration(seconds: 30),
    void Function(String)? onLog,
  }) => _enqueue(() async {
    try {
      await _ensureActive();
    } on HelperStartException catch (error) {
      return _startFailure(error);
    }
    return _parse(await _request(command, timeout: timeout, onLog: onLog));
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
    Process? process;
    try {
      final script = File('${scriptDir.path}/helper.sh');
      await script.writeAsString(_scriptSource, flush: true);

      final Process started;
      try {
        started = await Process.start('pkexec', [bash, script.path]);
      } on ProcessException catch (error) {
        throw HelperStartException(
          '无法执行 pkexec：${error.message}',
          unavailable: true,
        );
      }
      process = started;

      final stderrBuffer = StringBuffer();
      started.stderr
          .transform(utf8.decoder)
          .listen((chunk) {
            if (stderrBuffer.length < 2000) {
              stderrBuffer.write(chunk);
            }
          })
          .onError((_) {});

      final lines = StreamIterator(
        started.stdout
            .transform(utf8.decoder)
            .transform(const ProtocolLineSplitter()),
      );

      bool ready;
      try {
        ready = await lines.moveNext().timeout(const Duration(seconds: 120));
      } on TimeoutException {
        throw HelperStartException('管理员会话启动超时');
      }

      if (!ready || lines.current != 'READY') {
        throw await _describeStartFailure(started, stderrBuffer);
      }

      _process = started;
      _stdin = started.stdin;
      _lines = lines;
      unawaited(started.exitCode.then((_) => _handleExit(started)));
      onActiveChanged?.call();
    } catch (_) {
      // 启动失败：结束进程并清理临时脚本目录，下次操作重新授权。
      process?.kill();
      _clearScriptDir();
      rethrow;
    }
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

  Future<String> _request(
    String command, {
    Duration timeout = const Duration(seconds: 30),
    void Function(String)? onLog,
  }) async {
    final stdin = _stdin;
    final lines = _lines;
    if (stdin == null || lines == null) {
      throw HelperStartException('管理员会话未启动', unavailable: true);
    }
    try {
      stdin.writeln(command);
      await stdin.flush();
      while (true) {
        if (!await lines.moveNext().timeout(timeout)) {
          _reset();
          throw HelperStartException('管理员会话已结束，下次操作将重新授权');
        }
        final line = lines.current;
        // 空行不可能是协议响应（响应统一为 OK/ERR/UNAVAILABLE），忽略。
        if (line.isEmpty) {
          continue;
        }
        // 安装类命令的输出行：转发给调用方（对话框实时展示），继续等待终态。
        if (line.startsWith(_logPrefix)) {
          onLog?.call(line.substring(_logPrefix.length));
          continue;
        }
        return line;
      }
    } on TimeoutException {
      _process?.kill();
      _reset();
      throw HelperStartException('管理员会话响应超时');
    } on IOException catch (error) {
      _reset();
      throw HelperStartException('与管理员会话通信失败：$error');
    }
  }

  /// 命令输出行前缀（`LOG `）。
  static const _logPrefix = 'LOG ';

  HelperResult _parse(String response) {
    if (response == 'OK') {
      return HelperResult.ok;
    }
    if (response.startsWith('OK ')) {
      // 带数据的成功响应（如 `OK rustc 1.95.0 (…)`）。
      return HelperResult(HelperResultStatus.ok, response.substring(3));
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
    _clearScriptDir();
    onActiveChanged?.call();
  }

  /// 删除临时脚本目录（会话结束或启动失败时）。
  void _clearScriptDir() {
    final dir = _scriptDir;
    _scriptDir = null;
    if (dir != null) {
      unawaited(dir.delete(recursive: true).catchError((_) => dir));
    }
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
# 白名单：systemctl（daemon-reload 与 scx_loader 的 enable/disable）、
# scx_loader 配置与系统集成文件写入、scxctl 调用、apt 源码安装、
# Rust 工具链与 scx / scx-loader 的 cargo 编译安装（crates.io）。
set -o pipefail
B64=/usr/bin/base64
SYSTEMCTL=/usr/bin/systemctl
APT_GET=/usr/bin/apt-get
CARGO_HOME_DIR="${HOME:-/root}/.cargo"

export DEBIAN_FRONTEND=noninteractive
export PATH="$CARGO_HOME_DIR/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

emit_ok() { printf 'OK\n'; }
emit_err() {
  local msg="$*"
  msg=${msg//$'\n'/ }
  printf 'ERR %s\n' "$msg"
}
# 输出命令日志尾部（单行、限长），用于失败提示。
log_tail() { tail -n 3 "$1" 2>/dev/null | tr '\n' ' ' | cut -c1-400; }

# 执行命令并把输出逐行以 `LOG <行>` 转发给调用方（安装日志对话框），
# 同时留存输出用于失败摘要；返回命令自身的退出码。
# 注意：stdin 必须指向 /dev/null（防止子进程读取协议管道）；
# sed 需去掉全部 \r（dpkg 的进度输出以 \r 刷新，残留会让应用侧误断行）。
run_streamed() {
  local logf
  logf=$(mktemp)
  "$@" </dev/null 2>&1 | tee "$logf" | sed -u -e 's/\r//g' -e 's/^/LOG /'
  local code=${PIPESTATUS[0]}
  LOG_TAIL=$(log_tail "$logf")
  rm -f "$logf"
  return "$code"
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
      case "$action" in
        daemon-reload)
          if "$SYSTEMCTL" daemon-reload >/dev/null 2>&1; then
            emit_ok
          else
            emit_err 'systemctl daemon-reload 失败'
          fi
          ;;
        enable|disable)
          case "$unit" in
            scx_loader)
              if "$SYSTEMCTL" "$action" "$unit" >/dev/null 2>&1; then
                emit_ok
              else
                emit_err "systemctl $action $unit 失败"
              fi
              ;;
            *) emit_err 'systemctl 参数不允许' ;;
          esac
          ;;
        *) emit_err 'systemctl 参数不允许' ;;
      esac
      ;;
    WRITE)
      path=${rest%% *}
      data=${rest#* }
      case "$path" in
        /etc/scx_loader/config.toml|/etc/scx_loader.toml|/usr/share/scx_loader/config.toml|/usr/share/scx_loader.toml) ;;
        /usr/lib/systemd/system/scx_loader.service|/usr/share/dbus-1/system-services/org.scx.Loader.service|/usr/share/dbus-1/system.d/org.scx.Loader.conf|/usr/share/dbus-1/interfaces/org.scx.Loader.xml|/usr/share/polkit-1/actions/org.scx.Loader.policy) ;;
        *) emit_err '写入路径不允许'; continue ;;
      esac
      # 必须先建好父目录：否则下面的重定向会失败（曾误报为“配置数据解码失败”）。
      if ! mkdir -p "$(dirname "$path")"; then
        emit_err '创建目标目录失败'
        continue
      fi
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
    APT)
      action=${rest%% *}
      packages=${rest#* }
      case "$action" in
        update)
          if run_streamed "$APT_GET" -q update; then
            emit_ok
          else
            emit_err "apt update 失败：${LOG_TAIL:-未知错误}"
          fi
          ;;
        install)
          if [ -z "$packages" ] || [ "$packages" = "$action" ]; then
            emit_err '未指定软件包'; continue
          fi
          for pkg in $packages; do
            case "$pkg" in
              scx-scheds|scx-loader) ;;
              *) emit_err "不允许安装的软件包：$pkg"; continue 2 ;;
            esac
          done
          if run_streamed "$APT_GET" -y install $packages; then
            emit_ok
          else
            emit_err "软件包安装失败：${LOG_TAIL:-未知错误}"
          fi
          ;;
        *) emit_err 'APT 参数不允许' ;;
      esac
      ;;
    RUSTC_VERSION)
      out=$(rustc --version 2>/dev/null)
      if [ -n "$out" ]; then
        printf 'OK %s\n' "$out"
      else
        emit_err '未找到可用的 rustc'
      fi
      ;;
    RUSTUP_INSTALL)
      if ! command -v curl >/dev/null 2>&1; then
        emit_err '未找到 curl，无法下载 Rust 工具链'; continue
      fi
      # 全链路走国内镜像 rsproxy.cn：引导脚本、rustup 二进制、工具链组件。
      export RUSTUP_DIST_SERVER='https://rsproxy.cn'
      export RUSTUP_UPDATE_ROOT='https://rsproxy.cn/rustup'
      if run_streamed bash -o pipefail -c "curl --proto '=https' --tlsv1.2 -fsSL https://rsproxy.cn/rustup-init.sh | sh -s -- -y --default-toolchain stable --profile minimal --no-modify-path"; then
        emit_ok
      else
        emit_err "Rust 工具链安装失败：${LOG_TAIL:-未知错误}"
      fi
      ;;
    CARGO_INSTALL_LOADER)
      if run_streamed cargo --config 'source.crates-io.replace-with="rsproxy-sparse"' \
               --config 'source.rsproxy-sparse.registry="sparse+https://rsproxy.cn/index/"' \
               install --root /usr scx_loader scxctl; then
        emit_ok
      else
        emit_err "scx-loader 安装失败：${LOG_TAIL:-未知错误}"
      fi
      ;;
    CARGO_INSTALL_LAVD)
      if run_streamed cargo --config 'source.crates-io.replace-with="rsproxy-sparse"' \
               --config 'source.rsproxy-sparse.registry="sparse+https://rsproxy.cn/index/"' \
               install --root /usr scx_lavd; then
        emit_ok
      else
        emit_err "scx_lavd 调度器安装失败：${LOG_TAIL:-未知错误}"
      fi
      ;;
    *) emit_err '未知命令' ;;
  esac
done
''';
}
