import 'dart:io';

import '../models/scx_snapshot.dart';
import 'privileged_helper.dart';

/// 通过 systemctl 管理 scx_loader systemd 服务。
///
/// 状态读取不需要 root；启用/禁用开机自启通过 [PrivilegedHelper]
/// 执行（首次授权后可复用管理员会话）。
class SystemdController {
  SystemdController({PrivilegedHelper? helper})
    : _helper = helper ?? PrivilegedHelper();

  static const unitName = 'scx_loader';

  final PrivilegedHelper _helper;

  /// 读取服务运行/自启状态，读取本身不需要 root 权限。
  Future<SystemServiceState> serviceState() async {
    final active = await _check(['is-active', unitName], 'active');
    final enabled = await _check(['is-enabled', unitName], 'enabled');
    return SystemServiceState(active: active, enabled: enabled);
  }

  Future<bool> _check(List<String> arguments, String expected) async {
    try {
      final result = await Process.run('systemctl', arguments);
      return result.stdout.toString().trim() == expected;
    } on ProcessException {
      return false;
    }
  }

  /// 设置开机自启，返回错误信息，成功返回 null。
  Future<String?> setEnabled(bool enabled) async {
    final result = await _helper.setServiceEnabled(enabled: enabled);
    if (result.isOk) {
      return null;
    }
    return result.message ?? '设置开机自启失败';
  }
}
