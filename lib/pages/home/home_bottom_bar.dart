import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yaru/yaru.dart';

import 'home_controller.dart';

/// 侧边栏底部固定条目：关于。
class HomeBottomBar extends GetView<HomeController> {
  const HomeBottomBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final selected =
          controller.selectedIndex.value == HomeController.aboutIndex;
      // 稍微抬高，避免紧贴侧边栏底部。
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: YaruMasterTile(
          selected: selected,
          leading: const Icon(YaruIcons.question),
          title: const Text('关于应用'),
          onTap: () => controller.select(HomeController.aboutIndex),
        ),
      );
    });
  }
}
