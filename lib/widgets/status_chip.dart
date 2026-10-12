import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

/// 小圆角标签，用于展示模式、运行状态等短信息。
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.icon,
    this.color,
  });

  final String label;
  final IconData? icon;

  /// 前景与背景色基色，默认使用主题主色。
  final Color? color;

  /// “运行中/已启用”等成功状态色：浅色主题沿用 Yaru 原深绿（浅绿在
  /// 浅色底上太淡），深色主题改用浅绿（原深绿在深色底上偏暗）。
  static Color successColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? YaruColors.ubuntuMateGreen
        : YaruColors.light.success;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = color ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        // 底色减淡（alpha 调低）：半透明底在小字号下略显发糊。
        color: base.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: base),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: base,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
