import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../backend/models/sched_mode.dart';
import '../../../backend/models/scx_snapshot.dart';
import '../../../widgets/button_styles.dart';
import '../../../widgets/recommendation.dart';
import '../../../widgets/sched_mode_visuals.dart';
import '../../../widgets/status_chip.dart';

/// 调度模式单选列表。
class SchedModeSelector extends StatelessWidget {
  const SchedModeSelector({
    super.key,
    required this.info,
    required this.selected,
    required this.onChanged,
    this.runningMode,
  });

  final SchedulerInfo info;
  final SchedMode selected;
  final ValueChanged<SchedMode> onChanged;

  /// 本调度器当前实际运行的模式。
  ///
  /// 调度器未运行、不是本调度器，或使用自定义参数运行时为 null
  /// （此时没有“运行中的模式”可标记）。
  final SchedMode? runningMode;

  @override
  Widget build(BuildContext context) {
    if (info.loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      children: [
        for (final mode in SchedMode.values) _modeTile(context, mode),
      ],
    );
  }

  Widget _modeTile(BuildContext context, SchedMode mode) {
    final theme = Theme.of(context);
    final configured =
        mode == SchedMode.auto || info.configuredModes.contains(mode);
    final isRecommended =
        info.name == recommendedScheduler && mode == recommendedMode;
    final isRunningMode = runningMode == mode;

    return YaruRadioListTile<SchedMode>(
      value: mode,
      groupValue: selected,
      mouseCursor: kClickableMouseCursor,
      onChanged: configured
          ? (value) {
              if (value != null) {
                onChanged(value);
              }
            }
          : null,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(mode.label),
          // “运行中”位于“推荐”标识左侧。
          if (isRunningMode) ...[
            const SizedBox(width: 8),
            StatusChip(label: '运行中', color: StatusChip.successColor(context)),
          ],
          if (isRecommended) ...[
            const SizedBox(width: 8),
            const RecommendedChip(),
          ],
          if (!configured) ...[
            const SizedBox(width: 8),
            StatusChip(label: '未配置参数', color: theme.colorScheme.outline),
          ],
        ],
      ),
      subtitle: Text(mode.description),
      secondary: Icon(mode.icon),
    );
  }
}
