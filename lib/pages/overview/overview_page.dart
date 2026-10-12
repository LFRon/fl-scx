import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yaru/yaru.dart';

import '../../backend/app_state.dart';
import '../install/scx_install_view.dart';
import 'widgets/current_scheduler_card.dart';
import 'widgets/quick_actions_row.dart';
import 'widgets/system_status_section.dart';

/// 概览页：展示当前调度器状态与快捷操作。
///
/// scx 未安装时（统一的 [ScxAppState.scxInstalled] 开关为 false），
/// 直接显示安装引导页面。
class OverviewPage extends GetView<ScxAppState> {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return YaruDetailPage(
      // 详情区标题栏承担窗口标题栏角色（窗口控制按钮在窗口右上角）。
      appBar: YaruWindowTitleBar(
        leading: Navigator.of(context).canPop() ? const YaruBackButton() : null,
        title: const Text('概览'),
      ),
      body: Obx(() {
        if (!controller.scxInstalled.value) {
          return const ScxInstallView();
        }
        final snapshot = controller.snapshot.value;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            CurrentSchedulerCard(snapshot: snapshot),
            const SizedBox(height: 16),
            QuickActionsRow(state: controller),
            const SizedBox(height: 24),
            SystemStatusSection(snapshot: snapshot),
          ],
        );
      }),
    );
  }
}
