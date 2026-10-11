import 'package:dbus/dbus.dart';

import '../models/mode_args.dart';
import '../models/sched_mode.dart';
import 'dbus_error_text.dart';

/// `org.scx.Loader` D-Bus 接口的 Dart 客户端。
///
/// 所有控制操作（启动/切换/停止/重启/恢复默认）都通过 scx_loader 守护进程完成，
/// 只读查询（属性、模式参数）不需要授权，控制操作会触发 polkit 授权弹窗。
class ScxLoaderClient {
  ScxLoaderClient({DBusClient? client})
    : _client = client ?? DBusClient.system() {
    _object = DBusRemoteObject(
      _client,
      name: serviceName,
      path: objectPath,
    );
  }

  static const serviceName = 'org.scx.Loader';
  static const interfaceName = 'org.scx.Loader';
  static final objectPath = DBusObjectPath('/org/scx/Loader');

  /// 无调度器运行时的约定值。
  static const unknownScheduler = 'unknown';

  final DBusClient _client;
  late final DBusRemoteObject _object;

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ScxBackendException {
      rethrow;
    } catch (error) {
      throw ScxBackendException(describeDBusError(error));
    }
  }

  Future<DBusValue> _property(String name, String signature) => _guard(
    () => _object.getProperty(interfaceName, name, signature: DBusSignature(signature)),
  );

  Future<void> _call(
    String method,
    List<DBusValue> values, {
    DBusSignature? replySignature,
  }) => _guard(
    () => _object.callMethod(
      interfaceName,
      method,
      values,
      replySignature: replySignature,
      allowInteractiveAuthorization: true,
    ),
  );

  // ---------------------------------------------------------------------------
  // 只读属性
  // ---------------------------------------------------------------------------

  /// 当前正在运行的调度器，未运行为 `unknown`。
  Future<String> currentScheduler() async =>
      (await _property('CurrentScheduler', 's')).asString();

  /// 当前运行的调度模式。
  Future<SchedMode> currentMode() async =>
      SchedMode.fromRaw((await _property('SchedulerMode', 'u')).asUint32());

  /// 当前调度器运行参数，使用预设模式时为空。
  Future<List<String>> currentSchedulerArgs() async =>
      (await _property('CurrentSchedulerArgs', 'as')).asStringArray().toList();

  /// scx_loader 支持的调度器完整名列表。
  Future<List<String>> supportedSchedulers() async =>
      (await _property('SupportedSchedulers', 'as')).asStringArray().toList();

  /// 配置文件中配置的默认调度器。
  Future<String> defaultScheduler() async =>
      (await _property('DefaultScheduler', 's')).asString();

  /// 配置文件中配置的默认模式。
  Future<SchedMode> defaultMode() async =>
      SchedMode.fromRaw((await _property('DefaultMode', 'u')).asUint32());

  // ---------------------------------------------------------------------------
  // 只读方法
  // ---------------------------------------------------------------------------

  /// 查询指定调度器真正配置了参数的模式集合。
  Future<Set<SchedMode>> schedulerModes(String scxName) => _guard(() async {
    final response = await _object.callMethod(
      interfaceName,
      'SchedulerModes',
      [DBusString(scxName)],
      replySignature: DBusSignature('au'),
    );
    return response.returnValues.first
        .asUint32Array()
        .map(SchedMode.fromRaw)
        .toSet();
  });

  /// 查询指定调度器所有模式的解析参数。
  Future<List<ModeArgs>> schedulerModeArgs(String scxName) => _guard(() async {
    final response = await _object.callMethod(
      interfaceName,
      'SchedulerModeArgs',
      [DBusString(scxName)],
      replySignature: DBusSignature('a(uas)'),
    );
    return response.returnValues.first.asArray().map((value) {
      final fields = (value as DBusStruct).children;
      return ModeArgs(
        SchedMode.fromRaw(fields[0].asUint32()),
        fields[1].asStringArray().toList(),
      );
    }).toList();
  });

  // ---------------------------------------------------------------------------
  // 控制方法（可能触发 polkit 授权）
  // ---------------------------------------------------------------------------

  /// 以指定模式启动调度器。
  Future<void> startScheduler(String scxName, SchedMode mode) => _call(
    'StartScheduler',
    [DBusString(scxName), DBusUint32(mode.raw)],
    replySignature: DBusSignature(''),
  );

  /// 以自定义参数启动调度器。
  Future<void> startSchedulerWithArgs(String scxName, List<String> args) => _call(
    'StartSchedulerWithArgs',
    [DBusString(scxName), DBusArray.string(args)],
    replySignature: DBusSignature(''),
  );

  /// 切换到指定调度器与其模式。
  Future<void> switchScheduler(String scxName, SchedMode mode) => _call(
    'SwitchScheduler',
    [DBusString(scxName), DBusUint32(mode.raw)],
    replySignature: DBusSignature(''),
  );

  /// 切换到指定调度器并传入自定义参数。
  Future<void> switchSchedulerWithArgs(String scxName, List<String> args) => _call(
    'SwitchSchedulerWithArgs',
    [DBusString(scxName), DBusArray.string(args)],
    replySignature: DBusSignature(''),
  );

  /// 停止当前调度器。
  Future<void> stopScheduler() =>
      _call('StopScheduler', const [], replySignature: DBusSignature(''));

  /// 按原配置重启当前调度器。
  Future<void> restartScheduler() =>
      _call('RestartScheduler', const [], replySignature: DBusSignature(''));

  /// 恢复为配置文件中设置的默认调度器。
  Future<void> restoreDefault() =>
      _call('RestoreDefault', const [], replySignature: DBusSignature(''));

  Future<void> close() => _client.close();
}
