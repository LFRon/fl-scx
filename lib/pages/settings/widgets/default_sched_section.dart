import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yaru/yaru.dart';

import '../../../backend/models/mode_args.dart';
import '../../../backend/models/sched_mode.dart';
import '../../../widgets/action_feedback.dart';
import 'default_sched_controller.dart';

/// 开机默认调度设置（写入 scx_loader 配置文件）。
class DefaultSchedSection extends StatelessWidget {
  const DefaultSchedSection({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<DefaultSchedController>();

    return Obx(() {
      final theme = Theme.of(context);
      final app = controller.app;
      final snapshot = app.snapshot.value;
      final supported = snapshot.supportedSchedulers;
      final busy = app.busy.value;
      final scheduler = controller.scheduler.value;

      final currentText = snapshot.hasDefaultScheduler
          ? '${shortSchedulerName(snapshot.defaultScheduler)} · ${snapshot.defaultMode.label}'
          : '未配置';

      return YaruSection(
        headline: const Text('开机默认调度'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Text(
                'scx_loader 启动时会自动加载这里的调度器与模式，配置写入 ${snapshot.configPath}。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            YaruListTile(
              leading: const Icon(YaruIcons.ordered_list_new),
              title: const Text('默认调度器'),
              trailing: DropdownButton<String>(
                value: supported.contains(scheduler) ? scheduler : null,
                hint: const Text('未获取到列表'),
                onChanged: busy ? null : controller.selectScheduler,
                items: [
                  for (final name in supported)
                    DropdownMenuItem(
                      value: name,
                      child: Text('${shortSchedulerName(name)}（$name）'),
                    ),
                ],
              ),
            ),
            YaruListTile(
              leading: const Icon(YaruIcons.app_grid),
              title: const Text('默认模式'),
              trailing: DropdownButton<SchedMode>(
                value: controller.mode.value,
                onChanged: busy ? null : controller.selectMode,
                items: [
                  for (final mode in SchedMode.values)
                    DropdownMenuItem(
                      value: mode,
                      child: Text('${mode.label}（${mode.tomlName}）'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: (busy || scheduler == null)
                        ? null
                        : () => runBackendAction(
                            context,
                            controller.save,
                            successMessage: '已写入开机默认配置',
                          ),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('保存为开机默认'),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      '当前：$currentText',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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
