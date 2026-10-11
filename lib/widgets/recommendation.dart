import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../backend/models/sched_mode.dart';
import 'status_chip.dart';

/// 推荐的调度器与模式（界面显示“推荐”标识）。
const recommendedScheduler = 'scx_lavd';
const recommendedMode = SchedMode.auto;

/// 将推荐调度器排在列表最前（不存在时保持原顺序）。
List<String> sortedSchedulersRecommendedFirst(List<String> schedulers) {
  if (!schedulers.contains(recommendedScheduler)) {
    return schedulers;
  }
  return [
    recommendedScheduler,
    for (final name in schedulers)
      if (name != recommendedScheduler) name,
  ];
}

/// “推荐”标识。
class RecommendedChip extends StatelessWidget {
  const RecommendedChip({super.key});

  @override
  Widget build(BuildContext context) =>
      const StatusChip(label: '推荐', color: YaruColors.orange);
}
