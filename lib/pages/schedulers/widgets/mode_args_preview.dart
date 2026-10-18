import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../app/app_font.dart';
import '../../../backend/models/sched_mode.dart';
import '../../../backend/models/scx_snapshot.dart';

/// 展示所选模式由 scx_loader 解析出的实际参数。
class ModeArgsPreview extends StatelessWidget {
  const ModeArgsPreview({super.key, required this.info, required this.mode});

  final SchedulerInfo info;
  final SchedMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = info.argsFor(mode);
    final text = info.loading
        ? '正在读取 ${mode.label} 模式的参数…'
        : (entry == null || entry.args.isEmpty)
        ? '${mode.label} 模式没有额外参数，将使用调度器内置默认值'
        : entry.argsText;

    return YaruBorderContainer(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(
            YaruIcons.terminal,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                // 等宽字体通常不含 CJK：中文回退到打包字体，
                // 避免 ARM64 下回退到异常的系统字体。
                fontFamilyFallback: const [kAppFontFamily],
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
