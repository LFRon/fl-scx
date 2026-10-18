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

  /// 软件源（apt/dpkg）检查支持的发行版 ID：仅 Ubuntu、Debian、deepin，
  /// 其它发行版一律不做软件源检查。
  static const aptCheckDistroIds = <String>{'ubuntu', 'debian', 'deepin'};

  /// 解析 os-release 文本中的 ID（兼容引号写法）。
  static String? parseOsReleaseId(String text) {
    final match = RegExp(r'^ID=(.*)$', multiLine: true).firstMatch(text);
    if (match == null) {
      return null;
    }
    return match.group(1)!.trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
  }

  /// [id] 是否在软件源检查支持列表内。
  static bool aptCheckSupportedForId(String? id) =>
      id != null && aptCheckDistroIds.contains(id.toLowerCase());

  /// 当前发行版是否支持软件源检查（仅 Ubuntu / Debian / deepin）。
  static Future<bool> aptCheckSupported() async {
    try {
      final text = await File(osReleasePath).readAsString();
      return aptCheckSupportedForId(parseOsReleaseId(text));
    } on FileSystemException {
      return false;
    }
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
