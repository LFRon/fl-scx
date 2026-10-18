import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_font.dart';

/// 通知在屏幕上停留的最长总时长（含入场与退场动画）。
const _notificationLifetime = Duration(seconds: 2);

/// 通知入/退场动画时长。
///
/// 曲线与 Yaru 页面转场一致：位移 `fastOutSlowIn`，
/// 淡入 `easeIn`、淡出 `easeOutExpo`。
const _notificationAnimationDuration = Duration(milliseconds: 250);

/// 当前展示中的通知（同一时间只保留一条）。
OverlayEntry? _currentEntry;
GlobalKey<_AppNotificationState>? _currentKey;

/// 执行后端操作并根据结果显示通知。
Future<void> runBackendAction(
  BuildContext context,
  Future<String?> Function() action, {
  required String successMessage,
}) async {
  final error = await action();
  if (!context.mounted) {
    return;
  }
  showAppNotification(context, error ?? successMessage);
}

/// 统一的（Yaru 动画）通知展示：底部居中的浮层。
///
/// 入场位移用 [Curves.fastOutSlowIn]、淡入 [Curves.easeIn]，退场淡出
/// [Curves.easeOutExpo]，与 Yaru 页面转场同款；整条通知最长停留
/// [_notificationLifetime]，到点自动退场移除。展示中的旧通知会先开始
/// 退场，避免多条消息堆积。
void showAppNotification(BuildContext context, String message) {
  final overlay = Overlay.of(context);

  // 旧通知立即开始退场（其退场动画结束后会移除自身 entry）。
  _currentKey?.currentState?.dismiss();

  final key = GlobalKey<_AppNotificationState>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _AppNotification(
      key: key,
      message: message,
      onDismissed: () {
        if (identical(_currentEntry, entry)) {
          _currentEntry = null;
          _currentKey = null;
        }
        entry.remove();
      },
    ),
  );
  _currentEntry = entry;
  _currentKey = key;
  overlay.insert(entry);
}

class _AppNotification extends StatefulWidget {
  const _AppNotification({
    super.key,
    required this.message,
    required this.onDismissed,
  });

  final String message;
  final VoidCallback onDismissed;

  @override
  State<_AppNotification> createState() => _AppNotificationState();
}

class _AppNotificationState extends State<_AppNotification>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _notificationAnimationDuration,
  );

  /// 位移曲线：与 Yaru 页面转场一致。
  late final Animation<Offset> _offset =
      Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Curves.fastOutSlowIn,
          reverseCurve: Curves.fastOutSlowIn,
        ),
      );

  /// 透明度曲线：Yaru 转场淡入用 easeIn、淡出用 easeOutExpo。
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeIn,
    reverseCurve: Curves.easeOutExpo,
  );

  Timer? _hideTimer;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        widget.onDismissed();
      }
    });
    // 到达最长停留时长（含入场动画）时开始退场。
    _hideTimer = Timer(
      _notificationLifetime - _notificationAnimationDuration,
      _dismiss,
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// 立即开始退场（重复调用无效果）。
  void dismiss() => _dismiss();

  void _dismiss() {
    if (_dismissing) {
      return;
    }
    _dismissing = true;
    _hideTimer?.cancel();
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // 取色与 Material 3 的 SnackBar/Toast 规则一致：背景 inverseSurface、
    // 文字 onInverseSurface；字体显式钉在打包字体上，不依赖主题注入链路
    // （ARM64 下通知中的中文一旦回退到系统字体就会渲染异常）。
    final contentStyle = theme.textTheme.bodyMedium!.copyWith(
      color: colorScheme.onInverseSurface,
      fontFamily: kAppFontFamily,
    );
    return Positioned(
      left: 24,
      right: 24,
      bottom: 24 + MediaQuery.viewPaddingOf(context).bottom,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SlideTransition(
          position: _offset,
          child: FadeTransition(
            opacity: _opacity,
            child: Semantics(
              liveRegion: true,
              child: Material(
                color: colorScheme.inverseSurface,
                // 圆角与 AOSP toast 一致（frameworks/base toast_frame.xml，
                // 28dp）；不设 elevation，黑色背景无边缘阴影。
                borderRadius: BorderRadius.circular(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(widget.message, style: contentStyle),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
