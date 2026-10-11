import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yaru/yaru.dart';

import '../../backend/app_state.dart';
import '../../backend/models/mode_args.dart';

/// 关于页：应用说明、配置文件与内核 sched_ext 信息。
class AboutPage extends GetView<ScxAppState> {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return YaruDetailPage(
      appBar: AppBar(title: const Text('关于')),
      body: Obx(() {
        final snapshot = controller.snapshot.value;
        final ops = shortKernelOpsName(snapshot.kernelOps);
        final opsText = ops.isEmpty ? '无' : ops;

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            YaruSection(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const YaruListTile(
                    leading: Icon(YaruIcons.computer_filled),
                    title: Text('SCX 调度管理器'),
                    subtitle: Text(
                      '基于 Flutter + Yaru 的 sched_ext 图形化管理工具\n'
                      '通过 org.scx.Loader D-Bus 接口控制 scx_loader',
                    ),
                  ),
                  YaruListTile(
                    leading: const Icon(YaruIcons.history),
                    title: const Text('scx_loader 配置文件'),
                    subtitle: Text(
                      snapshot.configPath.isEmpty
                          ? '未找到'
                          : snapshot.configPath,
                    ),
                  ),
                  YaruListTile(
                    leading: const Icon(YaruIcons.question),
                    title: const Text('内核 sched_ext'),
                    subtitle: Text(
                      snapshot.kernelState.isEmpty
                          ? '未检测到 /sys/kernel/sched_ext'
                          : '状态：${snapshot.kernelState} · ops：$opsText',
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}
