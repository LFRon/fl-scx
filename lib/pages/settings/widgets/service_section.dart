import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yaru/yaru.dart';

import '../../../backend/app_state.dart';
import '../../../widgets/action_feedback.dart';
import '../../../widgets/button_styles.dart';
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
                    ? StatusChip.successColor(context)
                    : colors.warning,
              ),
            ),
            YaruListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('管理员会话'),
              subtitle: const Text(
                '本次运行首次特权操作弹出一次 pkexec 授权，'
                '之后切换调度器、写入配置等不再重复询问；应用退出后自动失效',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusChip(
                    label: controller.helperActive.value ? '已授权' : '未授权',
                    color: controller.helperActive.value
                        ? StatusChip.successColor(context)
                        : Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    style: kClickableButtonStyle,
                    onPressed: busy
                        ? null
                        : controller.helperActive.value
                        ? controller.deactivateHelper
                        : () => runBackendAction(
                            context,
                            controller.activateHelper,
                            successMessage: '管理员会话已激活',
                          ),
                    child: Text(
                      controller.helperActive.value ? '结束会话' : '立即授权',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}
