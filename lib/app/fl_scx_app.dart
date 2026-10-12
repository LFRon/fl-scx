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

  /// 小字号（bodySmall / labelMedium / labelSmall）统一 +3px。
  ///
  /// Yaru 默认分别为 12/12/10，中文界面下偏小；列表副标题、
  /// 状态标签与说明文字都取自这几个样式。
  static ThemeData _enlargeSmallFonts(ThemeData theme) {
    final text = theme.textTheme;
    TextStyle? bump(TextStyle? style) =>
        style?.copyWith(fontSize: (style.fontSize ?? 0) + 3);
    return theme.copyWith(
      textTheme: text.copyWith(
        bodySmall: bump(text.bodySmall),
        labelMedium: bump(text.labelMedium),
        labelSmall: bump(text.labelSmall),
      ),
      // 少量 Material ListTile 的副标题走 listTileTheme（主题内是旧样式副本）。
      listTileTheme: theme.listTileTheme.copyWith(
        subtitleTextStyle: bump(theme.listTileTheme.subtitleTextStyle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return YaruTheme(
      builder: (context, yaru, child) => GetMaterialApp(
        title: 'SCX 调度管理器',
        debugShowCheckedModeBanner: false,
        theme: _enlargeSmallFonts(yaru.theme),
        darkTheme: _enlargeSmallFonts(yaru.darkTheme),
        highContrastTheme: _enlargeSmallFonts(yaruHighContrastLight),
        highContrastDarkTheme: _enlargeSmallFonts(yaruHighContrastDark),
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
