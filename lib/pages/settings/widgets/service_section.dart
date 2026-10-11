import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yaru/yaru.dart';

import '../../../backend/app_state.dart';
import '../../../widgets/action_feedback.dart';
import '../../../widgets/status_chip.dart';

/// scx_loader systemd 服务设置。
class ServiceSection extends GetView<ScxAppState> {
  const ServiceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = YaruColors.of(context);

    return Obx(() {
      final snapshot = controller.snapshot.value;
      final busy = controller.busy.value;

      return YaruSection(
        headline: const Text('scx_loader 服务'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            YaruSwitchListTile(
              secondary: const Icon(YaruIcons.power),
              title: const Text('开机自动启动'),
              subtitle: const Text(
                '系统启动时自动加载 sched_ext 调度器（systemctl enable scx_loader）',
              ),
              value: snapshot.service.enabled,
              onChanged: busy
                  ? null
                  : (value) => runBackendAction(
                      context,
                      () => controller.setAutostart(value),
                      successMessage: value ? '已设置开机自启' : '已取消开机自启',
                    ),
            ),
            YaruListTile(
              leading: const Icon(YaruIcons.refresh),
              title: const Text('服务运行状态'),
              subtitle: const Text('scx_loader 由 D-Bus 按需激活'),
              trailing: StatusChip(
                label: snapshot.service.active ? '运行中' : '已停止',
                color: snapshot.service.active
                    ? colors.success
                    : colors.warning,
              ),
            ),
          ],
        ),
      );
    });
  }
}
