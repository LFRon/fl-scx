import 'dart:async';

import 'package:get/get.dart';

import 'config/loader_config.dart';
import 'dbus/dbus_error_text.dart';
import 'dbus/scx_loader_client.dart';
import 'kernel/kernel_sched_ext.dart';
import 'models/sched_mode.dart';
import 'models/scx_snapshot.dart';
import 'system/privileged_file_writer.dart';
import 'system/privileged_helper.dart';
import 'system/scx_control_service.dart';
import 'system/systemd_controller.dart';

/// 后端聚合状态：负责采集 scx / scx_loader / 内核 / systemd 信息，
/// 并向界面层暴露响应式快照与操作命令。
///
/// 所有命令返回 `null` 表示成功，否则返回可展示的错误信息。
///
/// 涉及 root 权限的操作统一经过 [PrivilegedHelper]：本次运行内首次
/// 操作弹出一次 pkexec 授权，之后复用管理员会话，直到应用退出。
///
/// 注意：控制器的状态变更（Rx 赋值）必须在构建阶段之外触发；
/// 页面初始同步请使用 post-frame 回调，避免在 build 期间标脏祖先组件。
class ScxAppState extends GetxController {
  factory ScxAppState({
    ScxLoaderClient? client,
    KernelSchedExt? kernel,
    PrivilegedHelper? helper,
    SystemdController? systemd,
    LoaderConfig? config,
    ScxControlService? control,
  }) {
    final loader = client ?? ScxLoaderClient();
    final privileged = helper ?? PrivilegedHelper();
    return ScxAppState._(
      client: loader,
      kernel: kernel ?? KernelSchedExt(),
      helper: privileged,
      systemd: systemd ?? SystemdController(helper: privileged),
      config:
          config ??
          LoaderConfig(writer: PrivilegedFileWriter(helper: privileged)),
      control: control ?? ScxControlService(dbus: loader, helper: privileged),
    );
  }

  ScxAppState._({
    required this._client,
    required this._kernel,
    required this._helper,
    required this._systemd,
    required this._config,
    required this._control,
  });

  /// 单次后端读取的超时时间。
  static const _readTimeout = Duration(seconds: 6);

  /// 后台自动刷新周期。
  static const _refreshInterval = Duration(seconds: 5);

  final ScxLoaderClient _client;
  final KernelSchedExt _kernel;
  final PrivilegedHelper _helper;
  final SystemdController _systemd;
  final LoaderConfig _config;
  final ScxControlService _control;
  Timer? _refreshTimer;

  /// 最近一次刷新得到的系统快照。
  final snapshot = ScxSnapshot.empty.obs;

  /// 是否有后端操作正在执行。
  final busy = false.obs;

  /// 管理员会话（root 辅助进程）是否已激活。
  final helperActive = false.obs;

  /// 各调度器的模式信息缓存（按调度器名索引）。
  final schedulerInfos = <String, SchedulerInfo>{}.obs;

  bool _refreshing = false;
  bool _pendingRefresh = false;

  @override
  void onInit() {
    super.onInit();
    _helper.onActiveChanged = () {
      helperActive.value = _helper.isActive;
    };
    helperActive.value = _helper.isActive;
    reload();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => reload());
  }

  @override
  void onClose() {
    _refreshTimer?.cancel();
    unawaited(_helper.stop());
    unawaited(_client.close());
    super.onClose();
  }

  /// 获取调度器详细信息（可能仍在加载）。
  SchedulerInfo infoFor(String scheduler) =>
      schedulerInfos[scheduler] ??
      SchedulerInfo(name: scheduler, loading: true);

  // ---------------------------------------------------------------------------
  // 管理员会话
  // ---------------------------------------------------------------------------

  /// 预先激活管理员会话（弹出一次 pkexec 授权），成功返回 null。
  Future<String?> activateHelper() async {
    busy.value = true;
    try {
      await _helper.ensureActive();
      return null;
    } on HelperStartException catch (error) {
      return error.message;
    } catch (error) {
      return '管理员会话启动失败：$error';
    } finally {
      busy.value = false;
      helperActive.value = _helper.isActive;
    }
  }

  /// 结束管理员会话；之后的特权操作会重新请求授权。
  Future<void> deactivateHelper() async {
    await _helper.stop();
    helperActive.value = _helper.isActive;
  }

  // ---------------------------------------------------------------------------
  // 信息刷新
  // ---------------------------------------------------------------------------

  /// 采集全部后端信息并更新快照。
  Future<void> reload() async {
    if (_refreshing) {
      // 已有刷新在进行时仅记录一次待刷新，结束后补一次，避免丢失更新。
      _pendingRefresh = true;
      return;
    }
    _refreshing = true;
    try {
      final kernelState = await _kernel.state();
      final kernelOps = await _kernel.runningOps();
      final service = await _systemd.serviceState();
      final configPath = await _config.locatePath();
      final defaults = await _config.readDefaults(configPath);

      var daemonAvailable = true;
      String? errorMessage;
      var currentScheduler = ScxLoaderClient.unknownScheduler;
      var currentMode = SchedMode.auto;
      var currentArgs = const <String>[];
      var supported = const <String>[];

      try {
        currentScheduler = await _client.currentScheduler().timeout(_readTimeout);
        currentMode = await _client.currentMode().timeout(_readTimeout);
        currentArgs = await _client.currentSchedulerArgs().timeout(_readTimeout);
        supported = await _client.supportedSchedulers().timeout(_readTimeout);
      } on ScxBackendException catch (error) {
        daemonAvailable = false;
        errorMessage = error.message;
      } on TimeoutException {
        daemonAvailable = false;
        errorMessage = '读取 scx_loader 信息超时';
      }

      final next = ScxSnapshot(
        daemonAvailable: daemonAvailable,
        currentScheduler: currentScheduler,
        currentMode: currentMode,
        currentArgs: currentArgs,
        supportedSchedulers: supported,
        defaultScheduler:
            defaults?.scheduler ?? ScxLoaderClient.unknownScheduler,
        defaultMode: defaults?.mode ?? SchedMode.auto,
        kernelState: kernelState,
        kernelOps: kernelOps,
        service: service,
        configPath: configPath,
        errorMessage: errorMessage,
      );
      // 仅在内容变化时更新，避免周期性刷新引起无意义的重建。
      if (next != snapshot.value) {
        snapshot.value = next;
      }
    } finally {
      _refreshing = false;
      if (_pendingRefresh) {
        _pendingRefresh = false;
        unawaited(reload());
      }
    }
  }

  /// 加载指定调度器的模式信息（带缓存）。
  ///
  /// 请勿在 build 期间调用：该方法在首个 await 之前会更新
  /// [schedulerInfos]。
  Future<void> ensureSchedulerInfo(String scheduler, {bool force = false}) async {
    final existing = schedulerInfos[scheduler];
    if (!force &&
        existing != null &&
        !existing.loading &&
        existing.error == null) {
      return;
    }
    if (!force && existing != null && existing.loading) {
      return;
    }

    schedulerInfos[scheduler] = (existing ?? SchedulerInfo(name: scheduler))
        .copyWith(loading: true, clearError: true);

    try {
      final configuredModes = await _client
          .schedulerModes(scheduler)
          .timeout(_readTimeout);
      final modeArgs = await _client
          .schedulerModeArgs(scheduler)
          .timeout(_readTimeout);
      schedulerInfos[scheduler] = SchedulerInfo(
        name: scheduler,
        configuredModes: configuredModes,
        modeArgs: modeArgs,
      );
    } catch (error) {
      schedulerInfos[scheduler] = SchedulerInfo(
        name: scheduler,
        error: describeDBusError(error),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // scx_loader 控制命令
  // （优先经管理员会话调用 scxctl，仍由 scx_loader 生效；不可用时回退 D-Bus）
  // ---------------------------------------------------------------------------

  /// 切换调度器：`args` 为空时使用 [mode] 的预设参数。
  Future<String?> switchScheduler({
    required String scheduler,
    required SchedMode mode,
    List<String> args = const <String>[],
  }) => _execute(
    () => _control.switchScheduler(scheduler: scheduler, mode: mode, args: args),
  );

  /// 停止当前调度器。
  Future<String?> stopScheduler() => _execute(_control.stopScheduler);

  /// 按原配置重启当前调度器。
  Future<String?> restartScheduler() => _execute(_control.restartScheduler);

  /// 恢复配置文件中设置的默认调度器。
  Future<String?> restoreDefault() => _execute(_control.restoreDefault);

  // ---------------------------------------------------------------------------
  // 配置 / systemd 命令（管理员会话）
  // ---------------------------------------------------------------------------

  /// 将 [scheduler] + [mode] 写入 scx_loader 配置文件作为开机默认。
  Future<String?> saveDefaultScheduler({
    required String scheduler,
    required SchedMode mode,
  }) => _execute(
    () => _config.writeDefaults(scheduler: scheduler, mode: mode),
  );

  /// 启用/禁用 scx_loader 服务开机自启。
  Future<String?> setAutostart(bool enabled) =>
      _execute(() => _systemd.setEnabled(enabled));

  // ---------------------------------------------------------------------------
  // 命令执行
  // ---------------------------------------------------------------------------

  /// 执行一个后端命令：管理 [busy]，完成后刷新快照并同步管理员会话状态。
  Future<String?> _execute(Future<String?> Function() action) async {
    busy.value = true;
    String? error;
    try {
      error = await action();
    } on ScxBackendException catch (exception) {
      error = exception.message;
    } on HelperStartException catch (exception) {
      error = exception.message;
    } catch (exception) {
      error = describeDBusError(exception);
    } finally {
      busy.value = false;
      helperActive.value = _helper.isActive;
    }
    // 刷新快照以同步界面；刷新失败不应影响命令结果。
    try {
      await reload();
    } catch (_) {}
    return error;
  }
}
