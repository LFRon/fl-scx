import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

/// 后端信息不可用或操作失败时的提示框。
class BackendInfoBox extends StatelessWidget {
  const BackendInfoBox({
    super.key,
    required this.message,
    this.title = 'scx_loader 不可用',
    this.type = YaruInfoType.danger,
  });

  final String message;
  final String title;
  final YaruInfoType type;

  @override
  Widget build(BuildContext context) {
    return YaruInfoBox(
      yaruInfoType: type,
      title: Text(title),
      subtitle: Text(message),
    );
  }
}
