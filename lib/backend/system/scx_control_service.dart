import 'dart:io';

import '../dbus/scx_loader_client.dart';
import '../models/sched_mode.dart';
import 'privileged_helper.dart';

/// 调度器控制路由。
///
/// 通过已授权的 root 辅助进程调用 `scxctl`：调度器仍由 scx_loader
/// 守护进程控制，但本次运行内首次授权后不再重复弹窗。
///
/// 每个操作只执行一次、不重试也不回退其它通道：失败直接返回错误
/// 由界面提示（例如 scxctl 缺失、授权被取消、参数不被调度器支持）。
class ScxControlService {
  ScxControlService({ScxLoaderClient? dbus, PrivilegedHelper? helper})
    : _dbus = dbus ?? ScxLoaderClient(),
      _helper = helper ?? PrivilegedHelper();

  static const _scxctlCandidates = <String>[
    '/usr/bin/scxctl',
    '/usr/local/bin/scxctl',
  ];

  final ScxLoaderClient _dbus;
  final PrivilegedHelper _helper;

  String? _scxctlPath;
  bool _scxctlResolved = false;

  /// 切换/启动调度器：`args` 为空时使用 [mode] 的预设参数。
  ///
  /// scxctl 的 `switch` 要求当前已有调度器在运行，停止状态下必须改用
  /// `start`，因此这里先查询运行状态再选择子命令。
  Future<String?> switchScheduler({
    required String scheduler,
    required SchedMode mode,
    List<String> args = const <String>[],
  }) async {
    final startFresh = await _isNoSchedulerRunning();
    return _run(
      buildArguments(
        start: startFresh,
        scheduler: scheduler,
        mode: mode,
        args: args,
      ),
    );
  }

  /// 构建 `scxctl start|switch` 的参数列表。
  ///
  /// 注意：clap 不接受以 `-` 开头的分离参数值，`--args` 必须使用
  /// 内联 `--args=...` 形式，否则会被当作选项解析。
  static List<String> buildArguments({
    required bool start,
    required String scheduler,
    required SchedMode mode,
    List<String> args = const <String>[],
  }) {
    final argv = <String>[start ? 'start' : 'switch', '--sched', scheduler];
    if (args.isEmpty) {
      argv.addAll(['--mode', mode.cliName]);
    } else {
      argv.add('--args=${args.join(',')}');
    }
    return argv;
  }

  /// 停止当前调度器。
  Future<String?> stopScheduler() => _run(const ['stop']);

  /// 按原配置重启当前调度器。
  Future<String?> restartScheduler() => _run(const ['restart']);

  /// 经管理员会话调用 scxctl；单次执行，失败直接返回错误。
  Future<String?> _run(List<String> argv) async {
    final executable = _resolveScxctl();
    if (executable == null) {
      return '操作失败：未找到 scxctl（scx-loader 命令行客户端）';
    }
    final result = await _helper.runScxctl(
      executable: executable,
      arguments: argv,
    );
    return result.isOk ? null : (result.message ?? '操作失败');
  }

  /// 当前是否没有调度器在运行（此时应使用 scxctl start 而不是 switch）。
  Future<bool> _isNoSchedulerRunning() async {
    try {
      final current = await _dbus.currentScheduler();
      return current.isEmpty || current == ScxLoaderClient.unknownScheduler;
    } catch (_) {
      // 读取失败时保守使用 switch（运行中的场景更常见）。
      return false;
    }
  }

  /// 定位可用的 scxctl 可执行文件。
  String? _resolveScxctl() {
    if (_scxctlResolved) {
      return _scxctlPath;
    }
    _scxctlResolved = true;

    for (final path in _scxctlCandidates) {
      if (File(path).existsSync()) {
        _scxctlPath = path;
        return path;
      }
    }
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      final path = '$home/.cargo/bin/scxctl';
      if (File(path).existsSync()) {
        _scxctlPath = path;
        return path;
      }
    }
    return null;
  }
}
