import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../backend/models/mode_args.dart';
import '../../../backend/models/scx_snapshot.dart';
import '../../../widgets/sched_mode_visuals.dart';
import '../../../widgets/status_chip.dart';

/// 当前调度器状态大卡片。
class CurrentSchedulerCard extends StatelessWidget {
  const CurrentSchedulerCard({super.key, required this.snapshot});

  final ScxSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = YaruColors.of(context);
    final running = snapshot.schedulerRunning;

    return YaruBorderContainer(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            child: Icon(
              YaruIcons.computer_filled,
              size: 32,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前调度器',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  running
                      ? shortSchedulerName(snapshot.currentScheduler)
                      : (snapshot.daemonAvailable ? '未运行' : '不可用'),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  running
                      ? snapshot.currentScheduler
                      : 'scx_loader 当前没有运行任何 sched_ext 调度器',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (running)
                      StatusChip(
                        icon: snapshot.currentMode.icon,
                        label: '模式：${snapshot.currentMode.label}',
                        color: theme.colorScheme.primary,
                      ),
                    if (running && snapshot.currentArgs.isNotEmpty)
                      StatusChip(
                        icon: YaruIcons.terminal,
                        label: snapshot.currentArgs.join(' '),
                      ),
                    StatusChip(
                      icon: Icons.memory,
                      label: snapshot.kernelEnabled ? 'sched_ext 已启用' : 'sched_ext 未启用',
                      color: snapshot.kernelEnabled
                          ? colors.success
                          : colors.error,
                    ),
                    StatusChip(
                      icon: YaruIcons.power,
                      label: snapshot.service.active
                          ? 'scx_loader 运行中'
                          : 'scx_loader 已停止',
                      color: snapshot.service.active
                          ? colors.success
                          : colors.warning,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
