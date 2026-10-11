import 'package:flutter/widgets.dart';
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

  @override
  void onInit() {
    super.onInit();
    _snapshotWorker = ever(app.snapshot, (_) => _syncFromSnapshot());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isClosed) {
        _syncFromSnapshot();
      }
    });
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

  /// 首次填值：优先使用配置文件中已有的默认调度设置。
  void _syncFromSnapshot() {
    final snapshot = app.snapshot.value;
    final supported = snapshot.supportedSchedulers;

    final current = scheduler.value;
    if (current == null) {
      if (snapshot.hasDefaultScheduler) {
        scheduler.value = snapshot.defaultScheduler;
        mode.value = snapshot.defaultMode;
      } else if (supported.isNotEmpty) {
        scheduler.value = supported.first;
      }
      return;
    }

    if (supported.isNotEmpty && !supported.contains(current)) {
      scheduler.value = supported.first;
    }
  }
}
