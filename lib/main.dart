import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yaru/yaru.dart';

import 'app/fl_scx_app.dart';
import 'app/fl_scx_binding.dart';
import 'backend/app_state.dart';

Future<void> main() async {
  // 自定义 Binding：在事件进入渲染绑定前过滤 GTK 嵌入器在触摸屏与鼠标
  // 混用时重复发送的 Add 事件（否则触发 MouseTracker 断言），见
  // fl_scx_binding.dart；须先于其它任何 Binding 初始化。
  FlScxBinding();

  // 隐藏原生 GTK 标题栏：窗口的最小化/最大化/关闭与拖动改由应用内的
  // YaruWindowTitleBar 承担（窗口控制按钮显示在窗口右上角）。
  await YaruWindowTitleBar.ensureInitialized();

  // 静默完成 sched_ext 环境探测、支持列表与全部调度器模式信息的预加载，
  // 之后才 runApp：Linux 窗口在首帧时才显示，因此界面前不会出现
  // “scx 不可用”的瞬时状态，进入调度器页也不再需要现加载。
  final appState = Get.put<ScxAppState>(ScxAppState(), permanent: true);
  await appState.preload();

  runApp(const FlScxApp());
}
