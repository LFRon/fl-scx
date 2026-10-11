import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yaru/yaru.dart';

import '../../backend/app_state.dart';
import '../overview/overview_page.dart';
import '../schedulers/schedulers_page.dart';
import '../settings/settings_page.dart';
import 'home_master_tile.dart';

/// 应用外壳：在 Yaru 主从布局中展示各功能页面。
class HomePage extends GetView<ScxAppState> {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return YaruMasterDetailPage(
      length: homeSections.length,
      appBar: AppBar(
        title: const Text('SCX 调度管理器'),
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
      tileBuilder: (context, index, selected, availableWidth) =>
          buildHomeMasterTile(context, index, selected),
      pageBuilder: (context, index) => switch (index) {
        0 => const OverviewPage(),
        1 => const SchedulersPage(),
        _ => const SettingsPage(),
      },
    );
  }
}
