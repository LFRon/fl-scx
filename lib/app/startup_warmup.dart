import 'package:flutter/material.dart';

import '../pages/schedulers/schedulers_page.dart';
import '../pages/settings/settings_page.dart';

/// 启动预热层：在首帧把"调度器"与"设置"页完整构建并绘制一次
/// （垫在被主界面遮挡的下层，用户不可见），预热组件构建、字体字形
/// 光栅化与文本排版等一次性开销，避免首次点击这些页面时的小卡顿。
///
/// Linux 窗口在首帧渲染完成后才显示，因此这次预热绘制对用户完全不可见。
class StartupWarmup extends StatefulWidget {
  const StartupWarmup({super.key, required this.child});

  final Widget child;

  @override
  State<StartupWarmup> createState() => _StartupWarmupState();
}

class _StartupWarmupState extends State<StartupWarmup> {
  bool _warming = true;

  @override
  void initState() {
    super.initState();
    // 首帧（含预热绘制）完成后立即移除预热层。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _warming) {
        setState(() => _warming = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_warming) {
      return widget.child;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(child: ExcludeSemantics(child: const SchedulersPage())),
        IgnorePointer(child: ExcludeSemantics(child: const SettingsPage())),
        widget.child,
      ],
    );
  }
}
