import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../backend/models/mode_args.dart';
import '../../../backend/models/scheduler_operation.dart';
import '../../../widgets/action_feedback.dart';
import '../../../widgets/backend_info_box.dart';
import '../../../widgets/status_chip.dart';
import '../schedulers_controller.dart';
import 'mode_args_preview.dart';
import 'sched_mode_selector.dart';

/// 调度器详情与配置面板（右侧分栏，需在 [Obx] 作用域内使用）。
class SchedulerDetailPane extends StatelessWidget {
  const SchedulerDetailPane({
    super.key,
    required this.controller,
    required this.scheduler,
  });

  final SchedulersController controller;
  final String scheduler;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = YaruColors.of(context);
    final app = controller.app;
    final snapshot = app.snapshot.value;
    final info = app.infoFor(scheduler);
    final mode = controller.mode.value;
    final isRunning =
        snapshot.schedulerRunning && snapshot.currentScheduler == scheduler;
    final canApply = !app.busy.value && snapshot.daemonAvailable;
    final operation = app.activeOperation.value;
    final applyOperation =
        (operation == SchedulerOperation.start ||
            operation == SchedulerOperation.switchTo)
        ? operation
        : null;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        shortSchedulerName(scheduler),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isRunning) ...[
                        const SizedBox(width: 12),
                        StatusChip(label: '运行中', color: colors.success),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    scheduler,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: controller.reloadSelectedInfo,
              icon: const Icon(YaruIcons.refresh),
              tooltip: '重新读取模式信息',
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (info.error != null) ...[
          BackendInfoBox(
            title: '模式信息加载失败',
            message: info.error!,
            type: YaruInfoType.warning,
          ),
          const SizedBox(height: 16),
        ],
        Text('调度模式', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          '模式由 scx_loader 的预设参数定义，未配置参数的模式等同于使用调度器内置默认值。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        SchedModeSelector(
          info: info,
          selected: mode,
          onChanged: (value) => controller.mode.value = value,
        ),
        const SizedBox(height: 12),
        ModeArgsPreview(info: info, mode: mode),
        const SizedBox(height: 24),
        Text('自定义参数（可选）', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        TextField(
          controller: controller.customArgs,
          decoration: const InputDecoration(
            hintText: '例如：-m performance -w；留空则使用上方所选模式的预设参数',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: canApply
                  ? () => _apply(context, setAsDefault: false)
                  : null,
              icon: applyOperation != null
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(YaruIcons.power_filled),
              label: Text(applyOperation?.label ?? '立即应用'),
            ),
            OutlinedButton.icon(
              onPressed: canApply
                  ? () => _apply(context, setAsDefault: true)
                  : null,
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('应用并设为开机默认'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '提示：本次运行首次特权操作会弹出一次管理员授权（pkexec），'
          '之后切换调度器、写入开机默认等操作均不再重复询问；切换仍由 scx_loader 完成。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Future<void> _apply(
    BuildContext context, {
    required bool setAsDefault,
  }) => runBackendAction(
    context,
    () => controller.apply(setAsDefault: setAsDefault),
    successMessage: setAsDefault ? '已应用配置并写入开机默认' : '已应用调度配置',
  );
}
