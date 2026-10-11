import 'package:flutter/material.dart';

/// 新版 Flutter 中按钮的默认光标为 `WidgetStateMouseCursor.adaptiveClickable`，
/// 在桌面端解析为普通箭头（仅 Web 解析为手型）。
///
/// 这里统一显式指定“手型”点击光标；禁用状态仍保持普通箭头。
///
/// 用法：`FilledButton.icon(style: kClickableButtonStyle, ...)`；
/// IconButton 使用 `mouseCursor: SystemMouseCursors.click`。
const kClickableButtonStyle = ButtonStyle(
  mouseCursor: WidgetStateProperty<MouseCursor?>.fromMap(
    <WidgetStatesConstraint, MouseCursor?>{
      WidgetState.disabled: SystemMouseCursors.basic,
      WidgetState.any: SystemMouseCursors.click,
    },
  ),
);
