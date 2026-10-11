import 'privileged_helper.dart';

/// 写入需要 root 权限的文件（如 `/etc/scx_loader/config.toml`）。
///
/// 通过 [PrivilegedHelper]（pkexec 授权一次的管理员会话）写入，
/// 目标路径由辅助进程白名单校验。
class PrivilegedFileWriter {
  PrivilegedFileWriter({PrivilegedHelper? helper})
    : _helper = helper ?? PrivilegedHelper();

  final PrivilegedHelper _helper;

  /// 将 [content] 写入 [targetPath]，返回错误信息，成功返回 null。
  Future<String?> writeText(String targetPath, String content) async {
    final result = await _helper.writeConfigFile(
      path: targetPath,
      content: content,
    );
    if (result.isOk) {
      return null;
    }
    return result.message ?? '写入配置文件失败';
  }
}
