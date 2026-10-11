import 'dart:io';

import 'pkexec.dart';

/// 通过 pkexec + cp 写入需要 root 权限的文件（如
/// `/etc/scx_loader/config.toml`），授权弹窗由 polkit 提供。
class PrivilegedFileWriter {
  /// 将 [content] 写入 [targetPath]，返回错误信息，成功返回 null。
  Future<String?> writeText(String targetPath, String content) async {
    final tempFile = File(
      '${Directory.systemTemp.path}/fl_scx_${DateTime.now().millisecondsSinceEpoch}.toml',
    );
    try {
      await tempFile.writeAsString(content, flush: true);
      final result = await Process.run('pkexec', [
        '/usr/bin/cp',
        tempFile.path,
        targetPath,
      ]);
      if (result.exitCode == 0) {
        return null;
      }
      return describePkexecFailure(result, '写入配置文件失败');
    } on FileSystemException catch (error) {
      return '写入临时文件失败：$error';
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }
}
