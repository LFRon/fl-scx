import 'dart:async';

import 'package:get/get.dart';

import 'config/loader_config.dart';
import 'dbus/dbus_error_text.dart';
import 'dbus/scx_loader_client.dart';
import 'kernel/kernel_sched_ext.dart';
import 'models/sched_mode.dart';
import 'models/scx_snapshot.dart';
import 'system/systemd_controller.dart';

/// 后端聚合状态：负责采集 scx / scx_loader / 内核 / systemd 信息，
/// 并向界面层暴露响应式快照与操作命令。
///
/// 所有命令返回 `null` 表示成功，否则返回可展示的错误信息。
///
/// 注意：控制器的状态变更（Rx 赋值）必须在构建阶段之外触发；
/// 页面初始同步请使用 post-frame 回调，避免在 build 期间标脏祖先组件。
class ScxAppState extends GetxController {
  ScxAppState({
    ScxLoaderClient? client,
    KernelSchedExt? kernel,
    SystemdController? systemd,
    LoaderConfig? config,
  }) : _client = client ?? ScxLoaderClient(),
       _kernel = kernel ?? KernelSchedExt(),
       _systemd = systemd ?? SystemdController(),
       _config = config ?? LoaderConfig();

  /// 单次后端读取的超时时间。
  static const _readTimeout = Duration(seconds: 6);

  /// 后台自动刷新周期。
  static const _refreshInterval = Duration(seconds: 5);

  final ScxLoaderClient _client;
  final KernelSchedExt _kernel;
  final SystemdController _systemd;
  final LoaderConfig _config;
  Timer? _refreshTimer;

  /// 最近一次刷新得到的系统快照。
  final snapshot = ScxSnapshot.empty.obs;

  /// 是否有后端操作正在执行。
  final busy = false.obs;

  /// 各调度器的模式信息缓存（按调度器名索引）。
  final schedulerInfos = <String, SchedulerInfo>{}.obs;

  bool _refreshing = false;
  bool _pendingRefresh = false;

  @override
  void onInit() {
    super.onInit();
    reload();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => reload());
  }

  @override
  void onClose() {
    _refreshTimer?.cancel();
    unawaited(_client.close());
    super.onClose();
  }

  /// 获取调度器详细信息（可能仍在加载）。
  SchedulerInfo infoFor(String scheduler) =>
      schedulerInfos[scheduler] ??
      SchedulerInfo(name: scheduler, loading: true);

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
  // scx_loader 控制命令（D-Bus，可能需要 polkit 授权）
  // ---------------------------------------------------------------------------

  /// 切换调度器：`args` 为空时使用 [mode] 的预设参数。
  Future<String?> switchScheduler({
    required String scheduler,
    required SchedMode mode,
    List<String> args = const <String>[],
  }) => _run(
    () => args.isEmpty
        ? _client.switchScheduler(scheduler, mode)
        : _client.switchSchedulerWithArgs(scheduler, args),
  );

  /// 停止当前调度器。
  Future<String?> stopScheduler() => _run(_client.stopScheduler);

  /// 按原配置重启当前调度器。
  Future<String?> restartScheduler() => _run(_client.restartScheduler);

  /// 恢复配置文件中设置的默认调度器。
  Future<String?> restoreDefault() => _run(_client.restoreDefault);

  // ---------------------------------------------------------------------------
  // 配置 / systemd 命令（pkexec 授权）
  // ---------------------------------------------------------------------------

  /// 将 [scheduler] + [mode] 写入 scx_loader 配置文件作为开机默认。
  Future<String?> saveDefaultScheduler({
    required String scheduler,
    required SchedMode mode,
  }) => _runTask(
    () => _config.writeDefaults(scheduler: scheduler, mode: mode),
  );

  /// 启用/禁用 scx_loader 服务开机自启。
  Future<String?> setAutostart(bool enabled) =>
      _runTask(() => _systemd.setEnabled(enabled));

  /// 执行一个 D-Bus 控制命令：成功后刷新快照。
  Future<String?> _run(Future<void> Function() action) async {
    busy.value = true;
    try {
      await action();
      await reload();
      return null;
    } on ScxBackendException catch (error) {
      return error.message;
    } catch (error) {
      return describeDBusError(error);
    } finally {
      busy.value = false;
    }
  }

  /// 执行一个返回错误信息（或 null）的任务：无论成败都刷新快照，
  /// 以便界面同步展示配置/服务的最新状态。
  Future<String?> _runTask(Future<String?> Function() action) async {
    busy.value = true;
    try {
      final error = await action();
      await reload();
      return error;
    } on ScxBackendException catch (error) {
      return error.message;
    } catch (error) {
      return describeDBusError(error);
    } finally {
      busy.value = false;
    }
  }
}
