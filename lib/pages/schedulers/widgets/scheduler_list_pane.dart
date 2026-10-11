import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../backend/models/mode_args.dart';
import '../../../widgets/recommendation.dart';
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

    // 推荐调度器（lavd）存在时永远排在第一个。
    final ordered = sortedSchedulersRecommendedFirst(schedulers);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: ordered.length,
      itemBuilder: (context, index) {
        final name = ordered[index];
        final isSelected = name == selected;
        final isRunning = name == runningScheduler;
        final isRecommended = name == recommendedScheduler;

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
            // 推荐标识在“运行中”左侧。
            trailing: (isRunning || isRecommended)
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isRecommended) const RecommendedChip(),
                      if (isRecommended && isRunning)
                        const SizedBox(width: 8),
                      if (isRunning)
                        StatusChip(label: '运行中', color: colors.success),
                    ],
                  )
                : null,
          ),
        );
      },
    );
  }
}
