import 'package:get/get.dart';

import '../../../backend/app_state.dart';
import '../../../backend/models/sched_mode.dart';

/// 设置页“开机默认调度”区域的界面状态。
class DefaultSchedController extends GetxController {
  DefaultSchedController(this.app);

  final ScxAppState app;

  /// 待写入的默认调度器（完整名）。
  final scheduler = Rxn<String>();

  /// 待写入的默认模式。
  final mode = SchedMode.auto.obs;

  Worker? _snapshotWorker;

  /// 上一次已同步进编辑器的配置默认值（用于识别配置是否真正变化）。
  String? _syncedScheduler;
  SchedMode? _syncedMode;

  @override
  void onInit() {
    super.onInit();
    _snapshotWorker = ever(app.snapshot, (_) => _syncFromSnapshot());
    // 在界面构建前（应用引导阶段）直接同步初始值：此时尚无组件订阅，
    // 不会出现构建期标脏；并保证启动预热帧渲染的是真实内容。
    _syncFromSnapshot();
  }

  @override
  void onClose() {
    _snapshotWorker?.dispose();
    super.onClose();
  }

  void selectScheduler(String? value) {
    if (value != null) {
      scheduler.value = value;
    }
  }

  void selectMode(SchedMode? value) {
    if (value != null) {
      mode.value = value;
    }
  }

  /// 写入配置文件，返回错误信息，成功返回 null。
  Future<String?> save() async {
    final target = scheduler.value;
    if (target == null) {
      return '尚未选择调度器';
    }
    return app.saveDefaultScheduler(scheduler: target, mode: mode.value);
  }

  /// 同步编辑器与配置文件中的实际默认值：
  ///
  /// - 配置中的默认值发生变化时（例如在调度器页“应用并设为开机默认”、
  ///   或外部修改了 config.toml），跟随更新，保证界面展示与配置文件
  ///   不脱节；
  /// - 配置未变化时保留用户正在选择、尚未保存的值，避免周期刷新抢改。
  void _syncFromSnapshot() {
    final snapshot = app.snapshot.value;
    final supported = snapshot.supportedSchedulers;

    if (snapshot.hasDefaultScheduler) {
      final changed =
          snapshot.defaultScheduler != _syncedScheduler ||
          snapshot.defaultMode != _syncedMode;
      if (!changed) {
        return;
      }
      _syncedScheduler = snapshot.defaultScheduler;
      _syncedMode = snapshot.defaultMode;
      scheduler.value = snapshot.defaultScheduler;
      mode.value = snapshot.defaultMode;
      return;
    }

    _syncedScheduler = null;
    _syncedMode = null;
    final current = scheduler.value;
    if (current == null) {
      if (supported.isNotEmpty) {
        scheduler.value = supported.first;
      }
      return;
    }
    if (supported.isNotEmpty && !supported.contains(current)) {
      scheduler.value = supported.first;
    }
  }
}
