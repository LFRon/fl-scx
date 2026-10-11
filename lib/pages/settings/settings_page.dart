import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yaru/yaru.dart';

import '../../backend/app_state.dart';
import 'widgets/about_section.dart';
import 'widgets/default_sched_section.dart';
import 'widgets/service_section.dart';

/// 设置页：服务自启动、开机默认调度与关于信息。
class SettingsPage extends GetView<ScxAppState> {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return YaruDetailPage(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          ServiceSection(),
          SizedBox(height: 16),
          DefaultSchedSection(),
          SizedBox(height: 16),
          AboutSection(),
        ],
      ),
    );
  }
}
