import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yaru/yaru.dart';

import '../../backend/app_state.dart';
import 'widgets/default_sched_section.dart';
import 'widgets/service_section.dart';

/// 设置页：服务自启动与开机默认调度。
class SettingsPage extends GetView<ScxAppState> {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return YaruDetailPage(
      // 详情区标题栏承担窗口标题栏角色（窗口控制按钮在窗口右上角）。
      appBar: YaruWindowTitleBar(
        leading: Navigator.of(context).canPop() ? const YaruBackButton() : null,
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          ServiceSection(),
          SizedBox(height: 16),
          DefaultSchedSection(),
        ],
      ),
    );
  }
}
