import 'package:flutter/material.dart';

/// 执行后端操作并根据结果显示 SnackBar。
Future<void> runBackendAction(
  BuildContext context,
  Future<String?> Function() action, {
  required String successMessage,
}) async {
  final error = await action();
  if (!context.mounted) {
    return;
  }
  showAppSnackBar(context, error ?? successMessage);
}

/// 统一的 SnackBar 展示。
void showAppSnackBar(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(message)));
}
