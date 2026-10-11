import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yaru/yaru.dart';

import '../../widgets/backend_info_box.dart';
import 'schedulers_controller.dart';
import 'widgets/scheduler_detail_pane.dart';
import 'widgets/scheduler_list_pane.dart';

/// 调度器页：左侧选择调度器，右侧配置模式与参数并应用。
class SchedulersPage extends StatelessWidget {
  const SchedulersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SchedulersController>();
    final app = controller.app;

    return YaruDetailPage(
      appBar: AppBar(title: const Text('调度器')),
      body: Column(
        children: [
          Obx(() {
            final snapshot = app.snapshot.value;
            if (snapshot.daemonAvailable) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.all(16),
              child: BackendInfoBox(
                message:
                    snapshot.errorMessage ?? '无法连接 scx_loader，暂时无法切换调度器',
              ),
            );
          }),
          Expanded(
            child: Obx(() {
              final snapshot = app.snapshot.value;
              final selected = controller.selected.value;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 280,
                    child: SchedulerListPane(
                      schedulers: snapshot.supportedSchedulers,
                      selected: selected,
                      runningScheduler: snapshot.schedulerRunning
                          ? snapshot.currentScheduler
                          : null,
                      daemonAvailable: snapshot.daemonAvailable,
                      onSelect: controller.select,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: selected == null
                        ? const Center(child: Text('请选择一个调度器'))
                        : SchedulerDetailPane(
                            controller: controller,
                            scheduler: selected,
                          ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}
