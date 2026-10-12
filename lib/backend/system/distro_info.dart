import 'dart:io';

/// 发行版与软件源探测（全部只读、无需授权）。
class DistroInfo {
  static const osReleasePath = '/etc/os-release';
  static const sourcesListPath = '/etc/apt/sources.list';
  static const sourcesDirPath = '/etc/apt/sources.list.d';

  /// Better Deepin REPO 的两个已知源地址（任一存在即可用）。
  static const betterDeepinRepoUrls = <String>[
    'https://obsci.odata.cc/Better-Deepin-REPO/Deepin_25/',
    'https://repo.odata.cc/deepin25/',
  ];

  /// 解析 os-release 文本中的 ID（兼容引号写法）。
  static String? parseOsReleaseId(String text) {
    final match = RegExp(r'^ID=(.*)$', multiLine: true).firstMatch(text);
    if (match == null) {
      return null;
    }
    return match.group(1)!.trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
  }

  /// 当前发行版是否为 deepin。
  static Future<bool> isDeepin() async {
    try {
      final text = await File(osReleasePath).readAsString();
      return parseOsReleaseId(text) == 'deepin';
    } on FileSystemException {
      return false;
    }
  }

  /// 文本是否包含 Better Deepin REPO 的源地址。
  static bool containsBetterDeepinRepo(String text) =>
      betterDeepinRepoUrls.any(text.contains);

  /// 系统 apt 源（sources.list 与 sources.list.d 下的 *.list / *.sources）
  /// 是否包含 Better Deepin REPO。
  static Future<bool> hasBetterDeepinRepo() async {
    final paths = <String>[sourcesListPath];
    try {
      await for (final entry in Directory(sourcesDirPath).list()) {
        if (entry is File &&
            (entry.path.endsWith('.list') || entry.path.endsWith('.sources'))) {
          paths.add(entry.path);
        }
      }
    } on FileSystemException {
      // 目录不存在时忽略。
    }
    for (final path in paths) {
      try {
        if (containsBetterDeepinRepo(await File(path).readAsString())) {
          return true;
        }
      } on FileSystemException {
        // 单个文件不可读时忽略。
      }
    }
    return false;
  }
}
