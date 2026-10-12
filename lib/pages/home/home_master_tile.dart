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

/// 双行条目的 CJK 文字墨迹在行盒内偏下（约 3 逻辑像素），
/// 使“图标+两行文字”整体视觉重心低于 Yaru 选项框中心；
/// 将标题/副标题绘制上移 3px 后，图标中心与文字视觉中间
/// 同时落在选项框中心（仅影响绘制，不影响布局）。
const _twoLineTextShift = Offset(0, -3);

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
