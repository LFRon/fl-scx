import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../backend/models/mode_args.dart';
import '../../../backend/models/scx_snapshot.dart';
import '../../../widgets/status_chip.dart';

/// 概览页系统状态明细列表。
class SystemStatusSection extends StatelessWidget {
  const SystemStatusSection({super.key, required this.snapshot});

  final ScxSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = YaruColors.of(context);
    final defaultsText = snapshot.hasDefaultScheduler
        ? '${shortSchedulerName(snapshot.defaultScheduler)} · ${snapshot.defaultMode.label}'
        : '未配置';

    return YaruSection(
      headline: const Text('系统状态'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          YaruListTile(
            leading: const Icon(YaruIcons.computer),
            title: const Text('内核 sched_ext'),
            subtitle: const Text('/sys/kernel/sched_ext/state'),
            trailing: StatusChip(
              label: snapshot.kernelEnabled ? '已启用' : '未启用',
              color: snapshot.kernelEnabled
                  ? StatusChip.successColor(context)
                  : colors.error,
            ),
          ),
          YaruListTile(
            leading: const Icon(YaruIcons.terminal),
            title: const Text('当前内核调度器（ops）'),
            subtitle: const Text('/sys/kernel/sched_ext/root/ops'),
            trailing: Text(
              shortKernelOpsName(snapshot.kernelOps).isEmpty
                  ? '（无）'
                  : shortKernelOpsName(snapshot.kernelOps),
            ),
          ),
          YaruListTile(
            leading: const Icon(YaruIcons.power),
            title: const Text('scx_loader 服务'),
            subtitle: Text(
              '由 D-Bus 按需激活 · 开机自启${snapshot.service.enabled ? '已开启' : '未开启'}',
            ),
            trailing: StatusChip(
              label: snapshot.service.active ? '运行中' : '已停止',
              color: snapshot.service.active
                  ? StatusChip.successColor(context)
                  : colors.warning,
            ),
          ),
          YaruListTile(
            leading: const Icon(YaruIcons.app_grid),
            title: const Text('支持调度器'),
            subtitle: const Text('由 scx_loader 提供'),
            trailing: Text('${snapshot.supportedSchedulers.length} 个'),
          ),
          YaruListTile(
            leading: const Icon(YaruIcons.ordered_list_new),
            title: const Text('开机默认调度'),
            subtitle: Text(snapshot.configPath),
            trailing: Text(defaultsText),
          ),
        ],
      ),
    );
  }
}
