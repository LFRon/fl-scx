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

  /// 切换调度器：`args` 为空时使用 [mode] 的预设参数。
  Future<String?> switchScheduler({
    required String scheduler,
    required SchedMode mode,
    List<String> args = const <String>[],
  }) {
    final argv = <String>['switch', '--sched', scheduler];
    if (args.isEmpty) {
      argv.addAll(['--mode', mode.cliName]);
    } else {
      argv.addAll(['--args', args.join(',')]);
    }
    return _run(
      argv,
      () => args.isEmpty
          ? _dbus.switchScheduler(scheduler, mode)
          : _dbus.switchSchedulerWithArgs(scheduler, args),
    );
  }

  /// 停止当前调度器。
  Future<String?> stopScheduler() =>
      _run(const ['stop'], _dbus.stopScheduler);

  /// 按原配置重启当前调度器。
  Future<String?> restartScheduler() =>
      _run(const ['restart'], _dbus.restartScheduler);

  /// 恢复配置文件中设置的默认调度器。
  Future<String?> restoreDefault() =>
      _run(const ['restore'], _dbus.restoreDefault);

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
