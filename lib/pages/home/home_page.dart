import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yaru/yaru.dart';

import '../../backend/app_state.dart';
import '../about/about_page.dart';
import '../overview/overview_page.dart';
import '../schedulers/schedulers_page.dart';
import '../settings/settings_page.dart';
import 'home_bottom_bar.dart';
import 'home_controller.dart';
import 'home_master_tile.dart';

/// 应用外壳：在 Yaru 主从布局中展示各功能页面。
class HomePage extends GetView<ScxAppState> {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final home = Get.find<HomeController>();

    return YaruMasterDetailPage(
      controller: home.pages,
      appBar: AppBar(
        title: DefaultTextStyle.merge(
          // 顶栏标题字号在此调整（继承主题颜色与字重）。
          style: const TextStyle(fontSize: 17),
          child: const Text('SCX 调度管理器'),
        ),
        actions: [
          Obx(
            () => controller.busy.value
                ? const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          IconButton(
            onPressed: controller.reload,
            icon: const Icon(YaruIcons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      bottomBar: const HomeBottomBar(),
      // 主列表点选后同步底部“关于”条目高亮状态。
      onSelected: home.syncSelection,
      tileBuilder: (context, index, selected, availableWidth) =>
          buildHomeMasterTile(context, index, selected),
      pageBuilder: (context, index) => switch (index) {
        0 => const OverviewPage(),
        1 => const SchedulersPage(),
        2 => const SettingsPage(),
        _ => const AboutPage(),
      },
    );
  }
}
