import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../backend/models/sched_mode.dart';
import '../../../backend/models/scx_snapshot.dart';
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
  });

  final SchedulerInfo info;
  final SchedMode selected;
  final ValueChanged<SchedMode> onChanged;

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

    return YaruRadioListTile<SchedMode>(
      value: mode,
      groupValue: selected,
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
