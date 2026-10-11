import 'package:dbus/dbus.dart';

/// scx_loader 后端操作失败时抛出的异常，携带可展示的中文信息。
class ScxBackendException implements Exception {
  ScxBackendException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 将 D-Bus 异常转换为界面可读的中文提示。
String describeDBusError(Object error) {
  if (error is DBusMethodResponseException) {
    final name = error.errorName;
    final raw = error.toString();

    if (name.contains('PolicyKit') ||
        name.contains('NotAuthorized') ||
        raw.contains('dismissed') ||
        raw.contains('Not authorized') ||
        raw.contains('Not allowed')) {
      return '授权失败或已取消，本次操作未执行';
    }
    if (name == 'org.freedesktop.DBus.Error.ServiceUnknown' ||
        name == 'org.freedesktop.DBus.Error.NameHasNoOwner') {
      return '无法连接 scx_loader 服务，请确认 scx_loader.service 可用';
    }
    if (name == 'org.freedesktop.DBus.AccessDenied') {
      return 'D-Bus 拒绝访问 scx_loader，请检查系统策略配置';
    }
    return 'scx_loader 返回错误：$raw';
  }
  if (error is DBusServiceUnknownException) {
    return '无法连接 scx_loader 服务，请确认 scx_loader.service 可用';
  }
  if (error is DBusClosedException) {
    return 'D-Bus 连接已断开';
  }
  return '操作失败：$error';
}
