import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../backend/models/mode_args.dart';
import '../../../widgets/status_chip.dart';

/// 调度器列表（左侧分栏）。
class SchedulerListPane extends StatelessWidget {
  const SchedulerListPane({
    super.key,
    required this.schedulers,
    required this.selected,
    required this.runningScheduler,
    required this.onSelect,
    this.daemonAvailable = true,
  });

  /// 支持的调度器完整名列表。
  final List<String> schedulers;

  /// 当前选中的调度器完整名。
  final String? selected;

  /// 正在运行的调度器完整名，未运行为 null。
  final String? runningScheduler;

  /// 选择回调。
  final ValueChanged<String> onSelect;

  /// scx_loader 是否可用。
  final bool daemonAvailable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = YaruColors.of(context);

    if (schedulers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          daemonAvailable ? '未获取到调度器列表' : 'scx_loader 不可用，无法列出调度器',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: schedulers.length,
      itemBuilder: (context, index) {
        final name = schedulers[index];
        final isSelected = name == selected;
        final isRunning = name == runningScheduler;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: ListTile(
            onTap: () => onSelect(name),
            selected: isSelected,
            selectedTileColor: theme.colorScheme.primary.withValues(
              alpha: 0.10,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kYaruContainerRadius),
            ),
            leading: Icon(
              isSelected ? YaruIcons.power_filled : YaruIcons.power,
              color: isSelected ? theme.colorScheme.primary : null,
            ),
            title: Text(shortSchedulerName(name)),
            subtitle: Text(name),
            trailing: isRunning
                ? StatusChip(label: '运行中', color: colors.success)
                : null,
          ),
        );
      },
    );
  }
}
