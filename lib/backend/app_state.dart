import 'dart:async';

import 'package:get/get.dart';

import 'config/loader_config.dart';
import 'dbus/dbus_error_text.dart';
import 'dbus/scx_loader_client.dart';
import 'kernel/kernel_sched_ext.dart';
import 'models/mode_args.dart';
import 'models/sched_mode.dart';
import 'models/scheduler_operation.dart';
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

  /// 启动预加载的整体超时时间。
  static const _bootstrapTimeout = Duration(seconds: 8);

  /// 后台自动刷新周期。
  static const _refreshInterval = Duration(seconds: 5);

  /// 等待内核调度状态收敛的超时时间与轮询间隔（600ms，避免过于频繁）。
  static const _settleTimeout = Duration(seconds: 10);
  static const _settleInterval = Duration(milliseconds: 600);

  /// “进行中”状态的最短展示时长：像“重启”这类瞬间完成的操作用户
  /// 也能看到“重启中”的反馈。
  static const _minOperationFeedback = Duration(milliseconds: 600);

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

  /// 当前进行中的调度器控制操作（null 表示空闲）。
  final activeOperation = Rxn<SchedulerOperation>();

  /// 管理员会话（root 辅助进程）是否已激活。
  final helperActive = false.obs;

  /// 各调度器的模式信息缓存（按调度器名索引）。
  final schedulerInfos = <String, SchedulerInfo>{}.obs;

  bool _refreshing = false;
  bool _pendingRefresh = false;
  bool _preloaded = false;

  /// 正在进行的模式信息加载（用于去重与等待）。
  final Map<String, Future<void>> _infoLoads = {};

  @override
  void onInit() {
    super.onInit();
    _helper.onActiveChanged = () {
      helperActive.value = _helper.isActive;
    };
    helperActive.value = _helper.isActive;
  }

  @override
  void onClose() {
    _refreshTimer?.cancel();
    unawaited(_helper.stop());
    unawaited(_client.close());
    super.onClose();
  }

  /// 静默预加载：探测 sched_ext 环境、加载支持列表与全部调度器模式信息。
  ///
  /// 由 `main()` 在 `runApp` 之前 await，确保界面显示时数据已就绪；
  /// 幂等，超时或异常时也会放行（周期刷新继续同步状态）。
  Future<void> preload() async {
    if (_preloaded) {
      return;
    }
    _preloaded = true;
    try {
      await _bootstrapInner().timeout(_bootstrapTimeout);
    } catch (_) {
      // 忽略：由周期刷新兜底。
    }
    _refreshTimer ??= Timer.periodic(_refreshInterval, (_) => reload());
  }

  Future<void> _bootstrapInner() async {
    await reload();
    await _warmupSchedulerInfos();
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
      // 若已有支持列表而部分调度器信息尚未缓存（如守护进程后启动），
      // 在后台预热，避免进入调度器页时才加载。
      _scheduleWarmupIfNeeded();
    } finally {
      _refreshing = false;
      if (_pendingRefresh) {
        _pendingRefresh = false;
        unawaited(reload());
      }
    }
  }

  /// 预加载所有支持调度器的模式信息。
  Future<void> _warmupSchedulerInfos() async {
    final schedulers = snapshot.value.supportedSchedulers;
    if (schedulers.isEmpty) {
      return;
    }
    await Future.wait(schedulers.map(ensureSchedulerInfo));
  }

  /// 支持列表存在缺失缓存时触发后台预热（已缓存/加载中会被去重）。
  void _scheduleWarmupIfNeeded() {
    final schedulers = snapshot.value.supportedSchedulers;
    if (schedulers.isEmpty) {
      return;
    }
    final missing = schedulers.any(
      (name) => schedulerInfos[name] == null && _infoLoads[name] == null,
    );
    if (missing) {
      unawaited(_warmupSchedulerInfos());
    }
  }

  /// 加载指定调度器的模式信息（带缓存与在途去重）。
  ///
  /// 请勿在 build 期间调用：该方法在首个 await 之前会更新
  /// [schedulerInfos]。
  Future<void> ensureSchedulerInfo(
    String scheduler, {
    bool force = false,
  }) async {
    final existing = schedulerInfos[scheduler];
    if (!force && existing != null && !existing.loading && existing.error == null) {
      return;
    }
    // 已在加载中：等待同一个在途请求，保证调用方（如启动预加载）
    // 能等到信息真正就绪。
    final inflight = _infoLoads[scheduler];
    if (!force && inflight != null) {
      await inflight;
      return;
    }

    final load = _loadSchedulerInfo(scheduler);
    _infoLoads[scheduler] = load;
    try {
      await load;
    } finally {
      if (identical(_infoLoads[scheduler], load)) {
        _infoLoads.remove(scheduler);
      }
    }
  }

  Future<void> _loadSchedulerInfo(String scheduler) async {
    final existing = schedulerInfos[scheduler];
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
  }) {
    final operation = snapshot.value.schedulerRunning
        ? SchedulerOperation.switchTo
        : SchedulerOperation.start;
    return _runSchedulerOperation(
      operation,
      action: () =>
          _control.switchScheduler(scheduler: scheduler, mode: mode, args: args),
      settled: (ops) => kernelOpsMatches(ops, scheduler),
    );
  }

  /// 停止当前调度器。
  Future<String?> stopScheduler() => _runSchedulerOperation(
    SchedulerOperation.stop,
    action: _control.stopScheduler,
    settled: (ops) => ops.trim().isEmpty,
  );

  /// 按原配置重启当前调度器。
  Future<String?> restartScheduler() => _runSchedulerOperation(
    SchedulerOperation.restart,
    action: _control.restartScheduler,
    // 重启期间 ops 会短暂清空再恢复，等待其重新出现即可。
    settled: (ops) => ops.trim().isNotEmpty,
  );

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
  // 命令执行与状态收敛
  // ---------------------------------------------------------------------------

  /// 执行一个后端命令：管理 [busy]，完成后刷新快照并同步管理员会话状态。
  Future<String?> _execute(Future<String?> Function() action) async {
    busy.value = true;
    String? error;
    try {
      error = await _perform(action);
    } finally {
      busy.value = false;
      helperActive.value = _helper.isActive;
    }
    await _safeReload();
    return error;
  }

  /// 执行调度器控制命令，并在命令被接受后等待内核实际状态收敛，
  /// 期间保持 [activeOperation] 让界面显示“启动中/停止中/…”并禁用按钮。
  ///
  /// scx_loader 的启停是异步的：D-Bus/scxctl 调用返回只代表命令被接受，
  /// 必须等待 `/sys/kernel/sched_ext/root/ops` 达到预期状态后再刷新界面。
  /// 收敛失败（例如自定义参数不被调度器支持导致进程启动失败）时返回
  /// 明确错误，而不是静默显示成功。
  Future<String?> _runSchedulerOperation(
    SchedulerOperation operation, {
    required Future<String?> Function() action,
    required bool Function(String kernelOps) settled,
  }) async {
    if (activeOperation.value != null) {
      return '已有调度器操作正在进行，请稍候';
    }

    busy.value = true;
    activeOperation.value = operation;
    String? error;
    try {
      error = await _perform(action);
      if (error == null) {
        // 收敛判定与最短反馈并行执行。
        final settledFuture = _awaitKernelSettled(settled);
        await Future<void>.delayed(_minOperationFeedback);
        if (!await settledFuture) {
          error = '调度器未能进入预期运行状态，请检查自定义参数是否被该调度器支持';
        }
      }
    } finally {
      activeOperation.value = null;
      busy.value = false;
      helperActive.value = _helper.isActive;
    }
    await _safeReload();
    return error;
  }

  /// 将后端异常映射为可展示的错误信息。
  Future<String?> _perform(Future<String?> Function() action) async {
    try {
      return await action();
    } on ScxBackendException catch (exception) {
      return exception.message;
    } on HelperStartException catch (exception) {
      return exception.message;
    } catch (exception) {
      return describeDBusError(exception);
    }
  }

  /// 轮询内核 sched_ext ops，直到**连续两次**（间隔一个轮询周期）
  /// 观测到预期状态或超时；达到返回 true，超时返回 false。
  ///
  /// 连续确认可避免把“旧调度器尚未卸载完成”的瞬时状态误判为成功
  /// ——例如切换携带无效参数时，旧进程仍短暂存在，随后新进程启动
  /// 失败、内核 ops 变空。
  Future<bool> _awaitKernelSettled(
    bool Function(String kernelOps) settled,
  ) async {
    final deadline = DateTime.now().add(_settleTimeout);
    var confirmedOnce = false;
    while (DateTime.now().isBefore(deadline)) {
      if (settled(await _kernel.runningOps())) {
        if (confirmedOnce) {
          return true;
        }
        confirmedOnce = true;
      } else {
        confirmedOnce = false;
      }
      await Future<void>.delayed(_settleInterval);
    }
    return false;
  }

  /// 刷新快照以同步界面；刷新失败不应影响已有结果。
  Future<void> _safeReload() async {
    try {
      await reload();
    } catch (_) {}
  }
}
