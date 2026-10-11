import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yaru/yaru.dart';

import '../../../backend/app_state.dart';
import '../../../backend/models/scheduler_operation.dart';
import '../../../widgets/action_feedback.dart';
import '../../../widgets/recommendation.dart';
import '../../schedulers/schedulers_controller.dart';

/// 概览页快捷操作按钮组。
///
/// 调度器运行时显示“停止调度器”；停止后该位置变为可点击的
/// “启动调度器”，启动目标为“调度器”页当前选中的调度器。
/// 末尾固定提供“应用推荐配置”按钮（推荐调度器 + 推荐模式，
/// 缺失或失败时弹通知）。
///
/// 操作进行中时对应按钮显示加载动画与“启动中/停止中/…”文字，
/// 并保持禁用，直到内核调度状态收敛。
///
/// 注意：本组件自带 [Obx]（GetX 只追踪 Obx builder 函数内直接发生的
/// Rx 读取，子组件 build 里的读取不会被祖先 Obx 记录），
/// 否则 busy/activeOperation 变化时按钮状态不会刷新。
class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key, required this.state});

  final ScxAppState state;

  @override
  Widget build(BuildContext context) {
    final schedulers = Get.find<SchedulersController>();

    return Obx(() {
      final snapshot = state.snapshot.value;
      final operation = state.activeOperation.value;
      final disabled = state.busy.value || !snapshot.daemonAvailable;
      final running = snapshot.schedulerRunning;

      // 启动/切换进行中时，即使快照已瞬时变为“运行中”，
      // 也保持展示带加载动画的启动/切换按钮，避免反馈丢失。
      final startActive =
          operation == SchedulerOperation.start ||
          operation == SchedulerOperation.switchTo;
      final showRunningActions = running && !startActive;

      final startTarget = schedulers.selected.value;
      final canStart = !disabled && startTarget != null;

      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          if (showRunningActions)
            FilledButton.icon(
              onPressed: disabled
                  ? null
                  : () => runBackendAction(
                      context,
                      state.restartScheduler,
                      successMessage: '已重启当前调度器',
                    ),
              icon: operation == SchedulerOperation.restart
                  ? _spinner
                  : const Icon(YaruIcons.refresh),
              label: Text(
                operation == SchedulerOperation.restart
                    ? SchedulerOperation.restart.label
                    : '重启调度器',
              ),
            )
          else
            Tooltip(
              message: startTarget != null
                  ? '启动 $startTarget（${schedulers.mode.value.label} 模式）'
                  : '请先在“调度器”页选择调度器',
              child: FilledButton.icon(
                onPressed: canStart
                    ? () => runBackendAction(
                        context,
                        () => _start(schedulers),
                        successMessage: '已启动调度器',
                      )
                    : null,
                icon: startActive
                    ? _spinner
                    : const Icon(Icons.play_arrow),
                label: Text(startActive ? operation!.label : '启动调度器'),
              ),
            ),
          if (showRunningActions)
            OutlinedButton.icon(
              onPressed: disabled
                  ? null
                  : () => runBackendAction(
                      context,
                      state.stopScheduler,
                      successMessage: '已停止当前调度器',
                    ),
              icon: operation == SchedulerOperation.stop
                  ? _spinner
                  : const Icon(YaruIcons.stop),
              label: Text(
                operation == SchedulerOperation.stop
                    ? SchedulerOperation.stop.label
                    : '停止调度器',
              ),
            ),
          OutlinedButton.icon(
            onPressed: disabled
                ? null
                : () => runBackendAction(
                    context,
                    _applyRecommended,
                    successMessage:
                        '已应用推荐配置（$recommendedScheduler · ${recommendedMode.label}）',
                  ),
            icon: const Icon(YaruIcons.star),
            label: const Text('应用推荐配置'),
          ),
        ],
      );
    });
  }

  static const _spinner = SizedBox(
    width: 16,
    height: 16,
    child: CircularProgressIndicator(strokeWidth: 2),
  );

  /// 启动调度器：启动“调度器”页当前选中的调度器。
  Future<String?> _start(SchedulersController schedulers) async {
    if (schedulers.selected.value != null) {
      return schedulers.apply(setAsDefault: false);
    }
    return '尚未选择调度器，请先在“调度器”页选择';
  }

  /// 应用推荐配置（推荐调度器 + 推荐模式）。
  ///
  /// 系统未提供推荐调度器或应用失败时，返回失败提示（界面弹通知）。
  Future<String?> _applyRecommended() async {
    final supported = state.snapshot.value.supportedSchedulers;
    if (!supported.contains(recommendedScheduler)) {
      return '应用推荐配置失败：当前系统未提供 $recommendedScheduler';
    }
    final error = await state.switchScheduler(
      scheduler: recommendedScheduler,
      mode: recommendedMode,
    );
    return error == null ? null : '应用推荐配置失败：$error';
  }
}
