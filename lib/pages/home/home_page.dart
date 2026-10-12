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
///
/// 顶栏使用 [YaruWindowTitleBar] 充当窗口标题栏（原生 GTK 标题栏已在
/// 启动时隐藏）：右上角为 Yaru 风格的窗口控制按钮，空白处可拖动窗口、
/// 双击最大化/还原。scx 未安装时（统一的 [ScxAppState.scxInstalled]
/// 开关为 false），侧边栏只保留“概览”，隐藏“调度器”与“设置”条目。
class HomePage extends GetView<ScxAppState> {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final home = Get.find<HomeController>();

    return Obx(() {
      final scxInstalled = controller.scxInstalled.value;

      return YaruMasterDetailPage(
        controller: home.pages,
        appBar: YaruWindowTitleBar(
          title: DefaultTextStyle.merge(
            // 顶栏标题字号在此调整（继承主题颜色与字重）。
            style: const TextStyle(fontSize: 17),
            child: const Text('SCX 调度管理器'),
          ),
          actions: [
            Obx(
              () => controller.busy.value
                  ? const Padding(
                      // 加载动画与右侧的间距在此调整：数值越大离窗口控制按钮越远。
                      padding: EdgeInsets.only(right: 15),
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
          ],
        ),
        bottomBar: const HomeBottomBar(),
        // 主列表点选后同步底部“关于”条目高亮状态。
        onSelected: home.syncSelection,
        tileBuilder: (context, index, selected, availableWidth) =>
            buildHomeMasterTile(
              context,
              index,
              selected,
              scxInstalled: scxInstalled,
            ),
        pageBuilder: (context, index) => switch (index) {
          0 => const OverviewPage(),
          1 when scxInstalled => const SchedulersPage(),
          2 when scxInstalled => const SettingsPage(),
          3 => const AboutPage(),
          // 未安装时隐藏条目的索引不可达，兜底回到概览（安装引导页）。
          _ => const OverviewPage(),
        },
      );
    });
  }
}
