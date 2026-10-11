import 'package:flutter/material.dart';

import '../backend/models/sched_mode.dart';

/// [SchedMode] 的界面视觉元素（图标等），与后端模型分离。
extension SchedModeVisuals on SchedMode {
  IconData get icon => switch (this) {
    SchedMode.auto => Icons.auto_mode_outlined,
    SchedMode.gaming => Icons.sports_esports_outlined,
    SchedMode.powerSave => Icons.energy_savings_leaf_outlined,
    SchedMode.lowLatency => Icons.speed_outlined,
    SchedMode.server => Icons.dns_outlined,
  };
}
