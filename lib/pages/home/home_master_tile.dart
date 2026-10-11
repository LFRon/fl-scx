import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

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

/// 应用的所有大页面。
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
    subtitle: '自启动、默认调度与关于',
  ),
];

/// 构建侧边栏条目。
Widget buildHomeMasterTile(BuildContext context, int index, bool selected) {
  final section = homeSections[index];
  return YaruMasterTile(
    leading: Icon(selected ? section.selectedIcon : section.icon),
    title: Text(section.title),
    subtitle: Text(section.subtitle),
  );
}
