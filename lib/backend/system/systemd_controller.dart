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

  /// 服务状态缓存时长：后台轮询（2.5s）无需每次都启动 systemctl 进程；
  /// 本应用修改（[setEnabled]）会立即使缓存失效，其它来源的变化最迟
  /// 10s 内可见。
  static const _stateCacheTtl = Duration(seconds: 10);

  final PrivilegedHelper _helper;

  SystemServiceState? _cachedState;
  DateTime? _cachedAt;

  /// 读取服务运行/自启状态，读取本身不需要 root 权限。
  ///
  /// 用一次 `systemctl show` 同时取回两个属性（避免启动两次进程），
  /// 结果在 [_stateCacheTtl] 内直接复用。
  Future<SystemServiceState> serviceState() async {
    final cached = _cachedState;
    final cachedAt = _cachedAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _stateCacheTtl) {
      return cached;
    }
    final state = await _readState();
    if (state == null) {
      // systemctl 不可用或读取失败：沿用上次结果，无缓存时视为未知。
      return cached ?? SystemServiceState.unknown;
    }
    _cachedState = state;
    _cachedAt = DateTime.now();
    return state;
  }

  /// 执行 `systemctl show` 并解析服务状态，失败返回 null。
  Future<SystemServiceState?> _readState() async {
    try {
      final result = await Process.run('systemctl', [
        'show',
        '--property=ActiveState',
        '--property=UnitFileState',
        unitName,
      ]);
      if (result.exitCode != 0) {
        return null;
      }
      return parseShowOutput(result.stdout.toString());
    } on ProcessException {
      return null;
    }
  }

  /// 解析 `systemctl show` 的 `Key=Value` 输出为服务状态。
  static SystemServiceState parseShowOutput(String output) {
    final properties = <String, String>{};
    for (final line in output.split('\n')) {
      final separator = line.indexOf('=');
      if (separator > 0) {
        properties[line.substring(0, separator)] = line
            .substring(separator + 1)
            .trim();
      }
    }
    return SystemServiceState(
      active: properties['ActiveState'] == 'active',
      enabled: properties['UnitFileState'] == 'enabled',
    );
  }

  /// 设置开机自启，返回错误信息，成功返回 null。
  Future<String?> setEnabled(bool enabled) async {
    final result = await _helper.setServiceEnabled(enabled: enabled);
    if (result.isOk) {
      // 使状态缓存失效，随后的刷新会立即读取新状态。
      _cachedState = null;
      _cachedAt = null;
      return null;
    }
    return result.message ?? '设置开机自启失败';
  }
}
