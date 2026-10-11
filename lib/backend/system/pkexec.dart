import 'dart:io';

/// pkexec 退出码 126：授权对话框被取消。
const pkexecAuthCancelledExitCode = 126;

/// pkexec 退出码 127：未获得授权或无法执行命令。
const pkexecNotAuthorizedExitCode = 127;

/// 将 pkexec 失败结果描述为中文错误。
String describePkexecFailure(ProcessResult result, String fallback) {
  final stderr = result.stderr.toString().trim();
  switch (result.exitCode) {
    case pkexecAuthCancelledExitCode:
      return '授权被取消，操作未执行';
    case pkexecNotAuthorizedExitCode:
      return '未获得授权，操作未执行';
    default:
      return stderr.isEmpty ? '$fallback（退出码 ${result.exitCode}）' : '$fallback：$stderr';
  }
}
