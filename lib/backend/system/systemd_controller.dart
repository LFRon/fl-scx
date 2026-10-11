import 'dart:io';

import '../models/scx_snapshot.dart';
import 'pkexec.dart';

/// 通过 systemctl 管理 scx_loader systemd 服务。
class SystemdController {
  static const unitName = 'scx_loader';

  /// 读取服务运行/自启状态，读取本身不需要 root 权限。
  Future<SystemServiceState> serviceState() async {
    final active = await _isActive();
    final enabled = await _isEnabled();
    return SystemServiceState(active: active, enabled: enabled);
  }

  Future<bool> _isActive() async {
    final result = await Process.run('systemctl', ['is-active', unitName]);
    return result.stdout.toString().trim() == 'active';
  }

  Future<bool> _isEnabled() async {
    final result = await Process.run('systemctl', ['is-enabled', unitName]);
    return result.stdout.toString().trim() == 'enabled';
  }

  /// 设置开机自启，通过 pkexec 获取管理员授权。
  ///
  /// 返回错误信息，成功返回 null。
  Future<String?> setEnabled(bool enabled) async {
    final result = await Process.run('pkexec', [
      '/usr/bin/systemctl',
      enabled ? 'enable' : 'disable',
      unitName,
    ]);
    if (result.exitCode == 0) {
      return null;
    }
    return describePkexecFailure(result, '设置开机自启失败');
  }
}
