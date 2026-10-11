import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../backend/app_state.dart';
import '../../../widgets/action_feedback.dart';

/// 概览页快捷操作按钮组（需在 [Obx] 作用域内使用）。
class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key, required this.state});

  final ScxAppState state;

  @override
  Widget build(BuildContext context) {
    final snapshot = state.snapshot.value;
    final disabled = state.busy.value || !snapshot.daemonAvailable;
    final canOperate = !disabled && snapshot.schedulerRunning;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton.icon(
          onPressed: canOperate
              ? () => runBackendAction(
                  context,
                  state.restartScheduler,
                  successMessage: '已重启当前调度器',
                )
              : null,
          icon: const Icon(YaruIcons.refresh),
          label: const Text('重启调度器'),
        ),
        OutlinedButton.icon(
          onPressed: canOperate
              ? () => runBackendAction(
                  context,
                  state.stopScheduler,
                  successMessage: '已停止当前调度器',
                )
              : null,
          icon: const Icon(YaruIcons.stop),
          label: const Text('停止调度器'),
        ),
        OutlinedButton.icon(
          onPressed: (!disabled && snapshot.hasDefaultScheduler)
              ? () => runBackendAction(
                  context,
                  state.restoreDefault,
                  successMessage: '已恢复默认调度器',
                )
              : null,
          icon: const Icon(YaruIcons.undo),
          label: const Text('恢复默认调度'),
        ),
      ],
    );
  }
}
