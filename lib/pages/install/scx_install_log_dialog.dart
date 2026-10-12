import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yaru/yaru.dart';

import '../../backend/system/scx_installation.dart';
import '../../widgets/button_styles.dart';
import 'scx_install_controller.dart';

/// 安装日志对话框：安装期间实时展示全部命令输出，结束后显示结果。
///
/// 对话框只读取 [ScxInstallController] 的状态；提前关闭不会中断安装
/// （安装继续在后台执行，安装页的进度行提供“查看安装日志”可再次打开）。
class ScxInstallLogDialog extends StatefulWidget {
  const ScxInstallLogDialog({
    super.key,
    required this.controller,
    required this.method,
  });

  final ScxInstallController controller;
  final ScxInstallMethod method;

  @override
  State<ScxInstallLogDialog> createState() => _ScxInstallLogDialogState();
}

class _ScxInstallLogDialogState extends State<ScxInstallLogDialog> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = YaruColors.of(context);
    final install = widget.controller;

    return Obx(() {
      final active = install.activeMethod.value != null;
      final error = install.installError.value;
      final progress = install.progress.value;
      final lines = install.logLines;

      // 追加新行后滚到底部；用户上翻查看历史时不打断。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) {
          return;
        }
        final position = _scroll.position;
        if (position.maxScrollExtent - position.pixels < 48) {
          _scroll.jumpTo(position.maxScrollExtent);
        }
      });

      final title = active
          ? (widget.method == ScxInstallMethod.apt
                ? '正在从软件源安装 scx'
                : '正在编译安装 scx 全家桶，请等待一定时间')
          : (error != null ? '安装失败' : '安装完成');
      final status = active
          ? (progress.isEmpty ? '正在执行…' : progress)
          : (error ?? 'scx 与 scx-loader 已安装完成');

      final screenWidth = MediaQuery.sizeOf(context).width;
      final contentWidth = screenWidth < 760 ? screenWidth - 120 : 640.0;

      return AlertDialog(
        title: Row(
          children: [
            if (active)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                error != null ? Icons.error_outline : Icons.check_circle_outline,
                size: 22,
                color: error != null ? colors.error : colors.success,
              ),
            const SizedBox(width: 12),
            Expanded(child: Text(title)),
          ],
        ),
        content: SizedBox(
          width: contentWidth,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                status,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: lines.isEmpty
                      ? Center(
                          child: Text(
                            '等待安装输出…',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : SelectionArea(
                          child: ListView.builder(
                            controller: _scroll,
                            itemCount: lines.length,
                            itemBuilder: (context, index) => Text(
                              lines[index],
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 15,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            style: kClickableButtonStyle,
            onPressed: () => Navigator.of(context).pop(),
            child: Text(active ? '后台继续' : '关闭'),
          ),
        ],
      );
    });
  }
}
