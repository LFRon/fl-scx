import 'package:flutter/material.dart';

/// 可用状态为“手型”、禁用状态为普通箭头。
MouseCursor _resolveClickableCursor(Set<WidgetState> states) {
  if (states.contains(WidgetState.disabled)) {
    return SystemMouseCursors.basic;
  }
  return SystemMouseCursors.click;
}

/// 新版 Flutter 中按钮/列表项默认光标为 `WidgetStateMouseCursor.adaptiveClickable`，
/// 在桌面端解析为普通箭头（仅 Web 解析为手型）。
///
/// 使用 `resolveWith` 构造（与 SDK 的 `adaptiveClickable` 一致）：
/// `fromMap` 生成的 mapper 被当作普通 [MouseCursor] 使用时（如
/// `MouseRegion`/`InkWell` 的光标）会在 `createSession` 抛错。
///
/// 用于接受 `MouseCursor` 的位置，例如 `ListTile.mouseCursor`、
/// `YaruRadioListTile.mouseCursor`；按钮样式 [kClickableButtonStyle] 复用它。
const kClickableMouseCursor = WidgetStateMouseCursor.resolveWith(
  _resolveClickableCursor,
  debugDescription: 'WidgetStateMouseCursor(clickable)',
);

/// 按钮统一样式：显式指定“手型”点击光标（禁用状态保持普通箭头）。
///
/// 用法：`FilledButton.icon(style: kClickableButtonStyle, ...)`。
const kClickableButtonStyle = ButtonStyle(mouseCursor: kClickableMouseCursor);
