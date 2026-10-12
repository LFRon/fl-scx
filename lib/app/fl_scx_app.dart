import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yaru/yaru.dart';

import '../pages/home/home_page.dart';
import 'app_bindings.dart';
import 'startup_warmup.dart';

/// 应用根组件：套用 Yaru 主题（跟随系统亮/暗色与强调色），
/// 并通过 GetX 注入状态控制器。
class FlScxApp extends StatelessWidget {
  const FlScxApp({super.key});

  /// 全局强制字体：ARM64 Desktop 下系统 CJK 字体回退异常，
  /// 应用中英文统一改用打包的 Noto Sans SC（见 pubspec.yaml 的 fonts 段）。
  static const _appFontFamily = 'Noto Sans SC';

  /// 构建带打包字体的 Yaru 主题。
  ///
  /// [createYaruLightTheme]/[createYaruDarkTheme] 支持 `fontFamily`，在构建期
  /// 注入字体后，AppBar/ListTile 等组件主题里 Yaru 预烤的字体副本会一并正确；
  /// 仅 SnackBar 的内容样式是 family-less 常量（工厂注入不到），在下方单独补
  /// 字体。颜色配方与 yaru 内置的 `yaruLight`/`yaruDark`/
  /// `yaruHighContrastLight`/`yaruHighContrastDark` 保持一致（含橙色变体的
  /// elevatedButtonColor 与高对比主题参数）。
  static ThemeData _yaruTheme({
    required YaruVariant variant,
    required bool dark,
    bool highContrast = false,
  }) {
    final ThemeData theme;
    if (highContrast) {
      theme = dark
          ? createYaruDarkTheme(
              primaryColor: Colors.white,
              highContrast: true,
              elevatedButtonTextColor: Colors.black,
              fontFamily: _appFontFamily,
            )
          : createYaruLightTheme(
              primaryColor: Colors.black,
              fontFamily: _appFontFamily,
            );
    } else if (dark) {
      theme = createYaruDarkTheme(
        primaryColor: variant.color,
        elevatedButtonColor: variant == YaruVariant.orange
            ? YaruColors.dark.success
            : null,
        fontFamily: _appFontFamily,
      );
    } else {
      theme = createYaruLightTheme(
        primaryColor: variant.color,
        elevatedButtonColor: variant == YaruVariant.orange
            ? YaruColors.light.success
            : null,
        fontFamily: _appFontFamily,
      );
    }

    // 小字号（bodySmall / labelMedium / labelSmall）统一 +3px：
    // Yaru 默认分别为 12/12/10，中文界面下偏小。
    final text = theme.textTheme;
    TextStyle? bump(TextStyle? style) =>
        style?.copyWith(fontSize: (style.fontSize ?? 0) + 3);
    return theme.copyWith(
      textTheme: text.copyWith(
        bodySmall: bump(text.bodySmall),
        labelMedium: bump(text.labelMedium),
        labelSmall: bump(text.labelSmall),
      ),
      // 少量 Material ListTile 的副标题走 listTileTheme（主题内是 labelMedium 副本）。
      listTileTheme: theme.listTileTheme.copyWith(
        subtitleTextStyle: bump(theme.listTileTheme.subtitleTextStyle),
      ),
      // Yaru 的通知（SnackBar）内容样式是 family-less 的 const TextStyle，
      // 工厂的 fontFamily 注入不到；补上字体，通知中的中文才不会回退到
      // 系统字体（ARM64 下渲染异常）。
      snackBarTheme: theme.snackBarTheme.copyWith(
        contentTextStyle: theme.snackBarTheme.contentTextStyle?.apply(
          fontFamily: _appFontFamily,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return YaruTheme(
      builder: (context, yaru, child) {
        // 未探测到系统变体时按 Yaru 默认的橙色处理。
        final variant = yaru.variant ?? YaruVariant.orange;
        return YaruTitleBarTheme(
          // 窗口控制按钮组：收紧按钮之间的间距（Yaru 默认 14）。
          data: const YaruTitleBarThemeData(buttonSpacing: 10),
          child: GetMaterialApp(
            title: 'SCX 调度管理器',
            debugShowCheckedModeBanner: false,
            theme: _yaruTheme(variant: variant, dark: false),
            darkTheme: _yaruTheme(variant: variant, dark: true),
            highContrastTheme: _yaruTheme(
              variant: variant,
              dark: false,
              highContrast: true,
            ),
            highContrastDarkTheme: _yaruTheme(
              variant: variant,
              dark: true,
              highContrast: true,
            ),
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
      },
    );
  }
}
