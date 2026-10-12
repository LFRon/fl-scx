import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app/fl_scx_app.dart';
import 'backend/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 静默完成 sched_ext 环境探测、支持列表与全部调度器模式信息的预加载，
  // 之后才 runApp：Linux 窗口在首帧时才显示，因此界面前不会出现
  // “scx 不可用”的瞬时状态，进入调度器页也不再需要现加载。
  final appState = Get.put<ScxAppState>(ScxAppState(), permanent: true);
  await appState.preload();

  runApp(const FlScxApp());
}
