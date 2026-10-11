import 'dart:io';

import '../models/sched_mode.dart';
import '../system/privileged_file_writer.dart';

/// 从 scx_loader 配置文件中解析出的默认调度设置。
class LoaderConfigDefaults {
  const LoaderConfigDefaults({this.scheduler, this.mode = SchedMode.auto});

  /// 默认调度器完整名，未配置为 null。
  final String? scheduler;

  /// 默认调度模式。
  final SchedMode mode;
}

/// 负责定位、解析与写入 scx_loader 的 TOML 配置文件。
///
/// 只读取 `default_sched` / `default_mode` 两个键；其它内容原样保留，
/// 写入时通过 [PrivilegedFileWriter]（pkexec）获得权限。
class LoaderConfig {
  LoaderConfig({PrivilegedFileWriter? writer})
    : _writer = writer ?? PrivilegedFileWriter();

  /// 与 scx_loader 自身一致的配置文件查找顺序。
  static const candidatePaths = <String>[
    '/etc/scx_loader/config.toml',
    '/etc/scx_loader.toml',
    '/usr/share/scx_loader/config.toml',
    '/usr/share/scx_loader.toml',
  ];

  /// 默认写入位置（配置文件不存在时使用）。
  static const defaultPath = '/etc/scx_loader/config.toml';

  static final _schedulerPattern = RegExp(
    r'^\s*default_sched\s*=\s*"([^"]*)"',
    multiLine: true,
  );
  static final _modePattern = RegExp(
    r'^\s*default_mode\s*=\s*"([^"]*)"',
    multiLine: true,
  );
  static final _defaultLinesPattern = RegExp(
    r'^[ \t]*default_(?:sched|mode)[ \t]*=.*\n?',
    multiLine: true,
  );

  /// 上次由本应用写入的管理注释横幅（重复应用时先移除，避免累积）。
  static final _managedHeaderPattern = RegExp(
    r'^[ \t]*# 由 fl_scx 写入[^\n]*\n?',
    multiLine: true,
  );

  final PrivilegedFileWriter _writer;

  /// 找到实际存在的配置文件路径，否则返回 [defaultPath]。
  Future<String> locatePath() async {
    for (final path in candidatePaths) {
      if (await File(path).exists()) {
        return path;
      }
    }
    return defaultPath;
  }

  /// 读取配置文件内容，失败返回 null。
  Future<String?> readText(String path) async {
    try {
      return await File(path).readAsString();
    } on FileSystemException {
      return null;
    }
  }

  /// 解析配置中的默认调度器与默认模式。
  Future<LoaderConfigDefaults?> readDefaults(String path) async {
    final text = await readText(path);
    if (text == null) {
      return null;
    }
    final schedulerMatch = _schedulerPattern.firstMatch(text);
    final modeMatch = _modePattern.firstMatch(text);
    final scheduler = schedulerMatch?.group(1);
    return LoaderConfigDefaults(
      scheduler: (scheduler == null || scheduler.isEmpty) ? null : scheduler,
      mode: modeMatch == null
          ? SchedMode.auto
          : SchedMode.fromTomlName(modeMatch.group(1)!),
    );
  }

  /// 在 [source] 基础上更新默认调度设置，保留其余内容。
  ///
  /// 重复应用时先移除上次写入的管理注释横幅与 default_* 行，
  /// 避免注释与空行不断累积。
  ///
  /// [args] 非空时，会一并写入/更新 `[scheds.<scheduler>]` 段内
  /// 所选模式的参数数组，使开机（scx_loader 启动）时同样携带
  /// 用户自定义参数生效。
  String applyDefaults(
    String source, {
    required String scheduler,
    required SchedMode mode,
    List<String> args = const <String>[],
  }) {
    final block = <String>[
      '# 由 fl_scx 写入：scx_loader 启动时自动应用的调度器与模式',
      'default_sched = "$scheduler"',
      'default_mode = "${mode.tomlName}"',
    ].join('\n');

    var body = source
        .replaceAll(_managedHeaderPattern, '')
        .replaceAll(_defaultLinesPattern, '')
        .trim();
    if (args.isNotEmpty) {
      body = _upsertModeArgs(body, scheduler: scheduler, mode: mode, args: args);
    }
    if (body.isEmpty) {
      return '$block\n';
    }
    return '$block\n\n$body\n';
  }

  /// 在 `[scheds.<scheduler>]` 段内写入/更新指定模式的参数数组；
  /// 段不存在时在末尾追加，其它内容保持不变。
  static String _upsertModeArgs(
    String body, {
    required String scheduler,
    required SchedMode mode,
    required List<String> args,
  }) {
    final key = mode.configKey;
    final value = '[${args.map(_tomlStringValue).join(', ')}]';
    final lines = body.split('\n');

    final headerIndex = lines.indexWhere(
      (line) => _isSectionHeader(line, scheduler),
    );
    if (headerIndex == -1) {
      return '${body.trimRight()}\n\n[scheds.$scheduler]\n$key = $value\n';
    }

    var sectionEnd = lines.length;
    for (var i = headerIndex + 1; i < lines.length; i++) {
      if (lines[i].trimLeft().startsWith('[')) {
        sectionEnd = i;
        break;
      }
    }

    final keyPattern = RegExp('^[ \t]*${RegExp.escape(key)}[ \t]*=');
    final keyIndex = () {
      for (var i = headerIndex + 1; i < sectionEnd; i++) {
        if (keyPattern.hasMatch(lines[i])) {
          return i;
        }
      }
      return -1;
    }();
    if (keyIndex != -1) {
      lines[keyIndex] = '$key = $value';
    } else {
      lines.insert(sectionEnd, '$key = $value');
    }
    return lines.join('\n');
  }

  static bool _isSectionHeader(String line, String scheduler) {
    final trimmed = line.trim();
    return trimmed == '[scheds.$scheduler]' ||
        trimmed == "[scheds.'$scheduler']" ||
        trimmed == '[scheds."$scheduler"]';
  }

  /// 将字符串编码为 TOML 双引号字符串。
  static String _tomlStringValue(String value) =>
      '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  /// 写入默认调度器与模式（可携带自定义参数），返回错误信息，成功返回 null。
  Future<String?> writeDefaults({
    required String scheduler,
    required SchedMode mode,
    List<String> args = const <String>[],
  }) async {
    final path = await locatePath();
    final source = await readText(path) ?? '';
    final updated = applyDefaults(
      source,
      scheduler: scheduler,
      mode: mode,
      args: args,
    );
    return _writer.writeText(path, updated);
  }
}
