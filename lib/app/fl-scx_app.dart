import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yaru/yaru.dart';

import '../pages/home/home_page.dart';
import 'app_bindings.dart';
import 'startup_warmup.dart';

/// 应用根组件：套用 Yaru 主题（跟随系统亮/暗色与强调色），
/// 并通过 GetX 注入状态控制器。
class ScxApp extends StatelessWidget {
  const ScxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return YaruTheme(
      builder: (context, yaru, child) => GetMaterialApp(
        title: 'SCX 调度管理器',
        debugShowCheckedModeBanner: false,
        theme: yaru.theme,
        darkTheme: yaru.darkTheme,
        highContrastTheme: yaruHighContrastLight,
        highContrastDarkTheme: yaruHighContrastDark,
        initialBinding: AppBindings(),
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          dragDevices: {
            PointerDeviceKind.mouse,
            PointerDeviceKind.touch,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          },
        ),
        home: const StartupWarmup(child: HomePage()),
      ),
    );
  }
}
