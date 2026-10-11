import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../backend/app_state.dart';
import '../../backend/models/sched_mode.dart';
import '../../widgets/recommendation.dart';

/// 调度器页的界面状态：当前选中的调度器、模式、自定义参数与操作。
///
/// 初始选择只在 post-frame 回调或 [ever] 观察者中同步，
/// 保证不会在构建阶段修改响应式状态。
class SchedulersController extends GetxController {
  SchedulersController(this.app);

  final ScxAppState app;

  /// 当前选中的调度器（完整名）。
  final selected = Rxn<String>();

  /// 期望应用的调度模式。
  final mode = SchedMode.auto.obs;

  /// 自定义参数输入。
  final customArgs = TextEditingController();

  Worker? _snapshotWorker;
  Worker? _infoWorker;

  @override
  void onInit() {
    super.onInit();
    _snapshotWorker = ever(app.snapshot, (_) => _syncSelection());
    _infoWorker = ever(app.schedulerInfos, (_) => _validateMode());
    // 在界面构建前（应用引导阶段）直接同步初始选择：此时尚无组件订阅
    // 这些 Rx，不会出现构建期标脏；同时保证启动预热帧能构建出真实的
    // 详情面板，首次进入本页不再有小卡顿。
    _syncSelection();
  }

  @override
  void onClose() {
    _snapshotWorker?.dispose();
    _infoWorker?.dispose();
    customArgs.dispose();
    super.onClose();
  }

  /// 选择调度器并加载其模式信息。
  void select(String scheduler) {
    selected.value = scheduler;
    customArgs.clear();
    _loadInfo(scheduler);
  }

  /// 重新读取当前调度器的模式信息。
  void reloadSelectedInfo() {
    final scheduler = selected.value;
    if (scheduler != null) {
      _loadInfo(scheduler, force: true);
    }
  }

  /// 应用当前选择：切换调度器，可选写入开机默认配置。
  ///
  /// 返回 null 表示成功，否则返回错误信息。
  Future<String?> apply({required bool setAsDefault}) async {
    final scheduler = selected.value;
    if (scheduler == null) {
      return '尚未选择调度器';
    }

    final error = await app.switchScheduler(
      scheduler: scheduler,
      mode: mode.value,
      args: splitArgs(customArgs.text),
    );
    if (error != null) {
      return error;
    }
    if (!setAsDefault) {
      return null;
    }

    final configError = await app.saveDefaultScheduler(
      scheduler: scheduler,
      mode: mode.value,
    );
    if (configError != null) {
      return '已切换调度器，但写入开机默认失败：$configError';
    }
    return null;
  }

  void _loadInfo(String scheduler, {bool force = false}) {
    unawaited(app.ensureSchedulerInfo(scheduler, force: force));
  }

  /// 模式信息加载完成后，若当前模式未被该调度器配置则回退到 Auto，
  /// 避免应用一个无参数的“空模式”。
  void _validateMode() {
    final scheduler = selected.value;
    if (scheduler == null) {
      return;
    }
    final info = app.infoFor(scheduler);
    if (info.loading || info.error != null) {
      return;
    }
    if (mode.value != SchedMode.auto &&
        !info.configuredModes.contains(mode.value)) {
      mode.value = SchedMode.auto;
    }
  }

  /// 确保选中项与最新的支持列表一致；首次进入时优先选中正在运行的调度器。
  void _syncSelection() {
    final snapshot = app.snapshot.value;
    final schedulers = snapshot.supportedSchedulers;
    if (schedulers.isEmpty) {
      return;
    }
    // 与列表显示顺序保持一致：推荐调度器（lavd）排在最前。
    final first = sortedSchedulersRecommendedFirst(schedulers).first;

    final current = selected.value;
    if (current == null) {
      final running =
          snapshot.schedulerRunning &&
          schedulers.contains(snapshot.currentScheduler);
      selected.value = running ? snapshot.currentScheduler : first;
      if (running) {
        mode.value = snapshot.currentMode;
      }
      _loadInfo(selected.value!);
      return;
    }

    if (!schedulers.contains(current)) {
      selected.value = first;
      _loadInfo(selected.value!);
    }
  }

  /// 将用户输入的自定义参数按空白切分。
  static List<String> splitArgs(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const [];
    }
    return trimmed.split(RegExp(r'\s+'));
  }
}
