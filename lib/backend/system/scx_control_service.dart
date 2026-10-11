import 'dart:io';

import '../dbus/dbus_error_text.dart';
import '../dbus/scx_loader_client.dart';
import '../models/sched_mode.dart';
import 'privileged_helper.dart';

/// 调度器控制路由。
///
/// 优先通过已授权的 root 辅助进程调用 `scxctl`：调度器仍由 scx_loader
/// 守护进程控制，但本次运行内首次授权后不再重复弹窗。
/// 当 scxctl 不可用时，回退到应用自身的 D-Bus 客户端
/// （会触发 scx_loader 的 polkit 交互授权）。
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
      () => args.isEmpty
          ? _dbus.switchScheduler(scheduler, mode)
          : _dbus.switchSchedulerWithArgs(scheduler, args),
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
  Future<String?> stopScheduler() =>
      _run(const ['stop'], _dbus.stopScheduler);

  /// 按原配置重启当前调度器。
  Future<String?> restartScheduler() =>
      _run(const ['restart'], _dbus.restartScheduler);

  /// 优先走 root 辅助进程 + scxctl；不可用时回退 D-Bus。
  Future<String?> _run(
    List<String> argv,
    Future<void> Function() fallback,
  ) async {
    final executable = _resolveScxctl();
    if (executable != null) {
      final result = await _helper.runScxctl(
        executable: executable,
        arguments: argv,
      );
      switch (result.status) {
        case HelperResultStatus.ok:
          return null;
        case HelperResultStatus.failed:
          // 包括用户取消授权与 scxctl 自身的错误，直接展示。
          return result.message ?? '操作失败';
        case HelperResultStatus.unavailable:
          break; // 辅助会话/ scxctl 不可用，尝试 D-Bus 回退
      }
    }

    try {
      await fallback();
      return null;
    } on ScxBackendException catch (error) {
      return error.message;
    } catch (error) {
      return describeDBusError(error);
    }
  }

  /// 当前是否没有调度器在运行（此时应使用 scxctl start 而不是 switch）。
  Future<bool> _isNoSchedulerRunning() async {
    try {
      final current = await _dbus.currentScheduler();
      return current.isEmpty ||
          current == ScxLoaderClient.unknownScheduler;
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
