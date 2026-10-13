import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import 'home_controller.dart';

/// 侧边栏（master）条目定义。
class HomeSection {
  const HomeSection({
    required this.icon,
    required this.selectedIcon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String title;
  final String subtitle;
}

/// 主列表中的页面（“关于”由底部固定条目呈现，不在此列）。
const homeSections = <HomeSection>[
  HomeSection(
    icon: YaruIcons.computer,
    selectedIcon: YaruIcons.computer_filled,
    title: '概览',
    subtitle: '运行状态与快捷操作',
  ),
  HomeSection(
    icon: YaruIcons.ordered_list_new,
    selectedIcon: YaruIcons.ordered_list_new,
    title: '调度器',
    subtitle: '选择与切换调度器',
  ),
  HomeSection(
    icon: YaruIcons.gear,
    selectedIcon: YaruIcons.gear_filled,
    title: '设置',
    subtitle: '自启动与默认调度',
  ),
];

/// 双行条目文字的绘制微调：Noto Sans SC 下整块文字墨迹相对选项框
/// 中心低约 1 逻辑像素，上移后与图标中心、选框中心对齐（仅影响绘制，
/// 不影响布局）；后续字体/字号调整时直接改这里的数值。
const _twoLineTextShift = Offset(0, -1);

/// 构建侧边栏条目；“关于”索引由底部条目承载，返回空占位。
///
/// scx 未安装时隐藏“调度器”与“设置”条目（对应页面也不可导航）。
Widget buildHomeMasterTile(
  BuildContext context,
  int index,
  bool selected, {
  required bool scxInstalled,
}) {
  if (index == HomeController.aboutIndex) {
    return const SizedBox.shrink();
  }
  if (!scxInstalled && index != 0) {
    return const SizedBox.shrink();
  }
  final section = homeSections[index];
  return YaruMasterTile(
    leading: Icon(selected ? section.selectedIcon : section.icon),
    title: Transform.translate(
      offset: _twoLineTextShift,
      child: Text(section.title),
    ),
    subtitle: Transform.translate(
      offset: _twoLineTextShift,
      child: Text(section.subtitle),
    ),
  );
}
