import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yaru/yaru.dart';

import '../../../backend/app_state.dart';
import '../../../backend/models/scheduler_operation.dart';
import '../../../widgets/action_feedback.dart';
import '../../schedulers/schedulers_controller.dart';

/// 概览页快捷操作按钮组（需在 [Obx] 作用域内使用）。
///
/// 调度器运行时显示“停止调度器”；停止后该位置变为可点击的
/// “启动调度器”，启动目标为“调度器”页当前选中的调度器
/// （没有选中项时回退到配置文件中的默认调度）。
///
/// 操作进行中时对应按钮显示加载动画与“启动中/停止中/…”文字，
/// 并保持禁用，直到内核调度状态收敛。
class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key, required this.state});

  final ScxAppState state;

  @override
  Widget build(BuildContext context) {
    final snapshot = state.snapshot.value;
    final operation = state.activeOperation.value;
    final disabled = state.busy.value || !snapshot.daemonAvailable;
    final running = snapshot.schedulerRunning;

    final schedulers = Get.find<SchedulersController>();
    final startTarget = schedulers.selected.value;
    final canStart =
        !disabled && (startTarget != null || snapshot.hasDefaultScheduler);

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        if (running)
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
                : '启动配置文件中的默认调度器',
            child: FilledButton.icon(
              onPressed: canStart
                  ? () => runBackendAction(
                      context,
                      () => _start(schedulers),
                      successMessage: '已启动调度器',
                    )
                  : null,
              icon: operation == SchedulerOperation.start
                  ? _spinner
                  : const Icon(Icons.play_arrow),
              label: Text(
                operation == SchedulerOperation.start
                    ? SchedulerOperation.start.label
                    : '启动调度器',
              ),
            ),
          ),
        if (running)
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
          onPressed: (!disabled && snapshot.hasDefaultScheduler)
              ? () => runBackendAction(
                  context,
                  state.restoreDefault,
                  successMessage: '已恢复默认调度器',
                )
              : null,
          icon: operation == SchedulerOperation.restore
              ? _spinner
              : const Icon(YaruIcons.undo),
          label: Text(
            operation == SchedulerOperation.restore
                ? SchedulerOperation.restore.label
                : '恢复默认调度',
          ),
        ),
      ],
    );
  }

  static const _spinner = SizedBox(
    width: 16,
    height: 16,
    child: CircularProgressIndicator(strokeWidth: 2),
  );

  /// 启动调度器：优先启动“调度器”页的当前选择，否则恢复默认调度。
  Future<String?> _start(SchedulersController schedulers) async {
    if (schedulers.selected.value != null) {
      return schedulers.apply(setAsDefault: false);
    }
    if (state.snapshot.value.hasDefaultScheduler) {
      return state.restoreDefault();
    }
    return '尚未选择调度器，请先在“调度器”页选择';
  }
}
