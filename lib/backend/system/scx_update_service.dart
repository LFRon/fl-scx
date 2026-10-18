import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'distro_info.dart';
import 'scx_installation.dart';

/// scx 的安装方式（更新检查视角的识别结果）。
enum ScxSetupKind {
  /// 由系统软件包管理器安装（dpkg 中的 scx-scheds 与 scx-loader，
  /// 不针对具体仓库做特判）。
  systemRepo,

  /// 经 cargo 编译安装（crates.io）。
  cargo,

  /// 无法识别安装方式。
  unknown,
}

/// 单个组件的版本检查状态。
enum ScxVersionState {
  /// 已安装版本不低于可用最新版本。
  upToDate,

  /// 存在可更新的新版本。
  updateAvailable,

  /// 版本信息缺失，无法判定。
  unknown,
}

/// 单个组件（软件包 / crate）的版本检查结果。
class ScxComponentCheck {
  const ScxComponentCheck({
    required this.name,
    this.installedVersion,
    this.latestVersion,
    this.state = ScxVersionState.unknown,
  });

  /// 软件包名或 crate 名（如 `scx-scheds`、`scx_loader`）。
  final String name;

  /// 已安装版本（无法读取时为 null）。
  final String? installedVersion;

  /// 软件源 / crates.io 中的最新版本（无法读取时为 null）。
  final String? latestVersion;

  final ScxVersionState state;
}

/// 一次更新检查的完整结果。
class ScxUpdateReport {
  const ScxUpdateReport({
    required this.setup,
    this.components = const [],
    this.note,
    this.cargoUserLevel = false,
  });

  final ScxSetupKind setup;

  final List<ScxComponentCheck> components;

  /// 附加说明（如软件源索引刷新失败、crates.io 不可达等）。
  final String? note;

  /// cargo 安装是否为用户级（`cargo install --list` 可见，即安装在
  /// ~/.cargo 下）：为 true 时覆盖更新走用户身份，无需管理员授权。
  final bool cargoUserLevel;

  /// 是否存在任一组件可更新。
  bool get hasUpdate =>
      components.any((c) => c.state == ScxVersionState.updateAvailable);
}

/// scx / scx-loader 的安装方式识别与更新检查。
///
/// - 系统源安装（仅 Ubuntu / Debian / deepin 发行版检查：dpkg 中
///   scx-scheds 与 scx-loader 均为已安装状态；其它发行版一律跳过该方式）：
///   以免 root 的方式把软件源索引刷新到用户缓存目录（apt 的
///   `Dir::State::Lists` / `Dir::Cache` 重定向），再用 apt-cache 读取
///   候选版本，与 dpkg 记录的已安装版本比对；
/// - cargo 安装：读取 `cargo install --list`（或二进制 `--version`）中的
///   已装版本，与 crates.io 上的最新稳定版本比对（优先 rsproxy 镜像的
///   sparse 索引，失败后回退官方 API）；
/// - 都无法识别时返回 [ScxSetupKind.unknown]，不做版本比对。
class ScxUpdateService {
  /// cargo 场景兜底检查的 crate（cargo install --list 读不到时）。
  static const cargoCrates = <String>['scx_loader', 'scx_lavd', 'scxctl'];

  static const _aptGet = '/usr/bin/apt-get';
  static const _aptCache = '/usr/bin/apt-cache';

  /// 免 root 刷新软件源索引的等待上限。
  static const _refreshTimeout = Duration(minutes: 3);

  static const _queryTimeout = Duration(seconds: 30);
  static const _httpTimeout = Duration(seconds: 20);
  static const _userAgent = 'fl-scx-update-check';

  /// 用户级 cargo 覆盖更新的等待上限（编译可能较久）。
  static const _cargoUpdateTimeout = Duration(minutes: 60);

  /// 执行一次更新检查；[onProgress] 回传阶段文本。
  Future<ScxUpdateReport> check({void Function(String)? onProgress}) async {
    onProgress?.call('正在识别安装方式…');
    final setup = await detectSetup();
    return switch (setup) {
      ScxSetupKind.systemRepo => _checkSystemRepo(onProgress: onProgress),
      ScxSetupKind.cargo => _checkCargo(onProgress: onProgress),
      ScxSetupKind.unknown => const ScxUpdateReport(
        setup: ScxSetupKind.unknown,
      ),
    };
  }

  /// 识别安装方式：系统源（仅 Ubuntu/Debian/deepin，dpkg 两个包都装）
  /// → cargo → 未知。
  Future<ScxSetupKind> detectSetup() async {
    var repoInstalled = false;
    if (await DistroInfo.aptCheckSupported()) {
      final text = await _readDpkgStatus();
      repoInstalled =
          text != null &&
          ScxInstallationService.aptPackages.every(
            (pkg) => ScxInstallationService.dpkgPackageInstalled(text, pkg),
          );
    }
    final cargoEvidence = repoInstalled ? false : await _hasCargoEvidence();
    return resolveSetup(
      repoPackagesInstalled: repoInstalled,
      cargoEvidence: cargoEvidence,
    );
  }

  /// 按“系统源优先、其次 cargo、否则未知”的规则确定安装方式。
  static ScxSetupKind resolveSetup({
    required bool repoPackagesInstalled,
    required bool cargoEvidence,
  }) {
    if (repoPackagesInstalled) {
      return ScxSetupKind.systemRepo;
    }
    if (cargoEvidence) {
      return ScxSetupKind.cargo;
    }
    return ScxSetupKind.unknown;
  }

  // ── 系统源安装 ──────────────────────────────────────────────────────

  Future<ScxUpdateReport> _checkSystemRepo({
    required void Function(String)? onProgress,
  }) async {
    final dpkgText = await _readDpkgStatus();
    final aptDir = _aptDir();
    onProgress?.call('正在以免 root 方式刷新软件源索引…');
    final refreshed = await _refreshAptLists(aptDir);
    onProgress?.call('正在读取软件源中的可用版本…');
    final candidates = await _aptCandidates(
      listsDir: refreshed ? aptDir : null,
    );
    final components = <ScxComponentCheck>[
      for (final pkg in ScxInstallationService.aptPackages)
        buildComponent(
          name: pkg,
          installed: dpkgText == null
              ? null
              : ScxInstallationService.dpkgPackageVersion(dpkgText, pkg),
          latest: candidates[pkg],
        ),
    ];
    return ScxUpdateReport(
      setup: ScxSetupKind.systemRepo,
      components: components,
      note: refreshed ? null : '软件源索引刷新失败，使用本地缓存的版本信息。',
    );
  }

  /// 免 root 的索引目录：`~/.cache/fl_scx/apt/{lists,cache}`。
  static Directory _aptDir() {
    final home = Platform.environment['HOME'];
    final base = home == null || home.isEmpty
        ? '${Directory.systemTemp.path}/fl_scx'
        : '$home/.cache/fl_scx';
    return Directory('$base/apt');
  }

  /// 以当前用户身份把软件源索引刷新到 [_aptDir]（不触碰系统目录）。
  Future<bool> _refreshAptLists(Directory aptDir) async {
    try {
      Directory('${aptDir.path}/lists/partial').createSync(recursive: true);
      Directory('${aptDir.path}/cache/partial').createSync(recursive: true);
      final result = await Process.run(
        _aptGet,
        [
          'update',
          '-o',
          'Debug::NoLocking=1',
          '-o',
          'Dir::State::Lists=${aptDir.path}/lists',
          '-o',
          'Dir::Cache=${aptDir.path}/cache',
        ],
        environment: {'LC_ALL': 'C'},
      ).timeout(_refreshTimeout);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 读取软件包候选版本；[listsDir] 为 null 时使用系统索引（可能较旧）。
  Future<Map<String, String?>> _aptCandidates({Directory? listsDir}) async {
    final args = <String>[
      if (listsDir != null) ...[
        '-o',
        'Debug::NoLocking=1',
        '-o',
        'Dir::State::Lists=${listsDir.path}',
        '-o',
        'Dir::Cache=${listsDir.parent.path}/cache',
      ],
      'policy',
      ...ScxInstallationService.aptPackages,
    ];
    try {
      final result = await Process.run(
        _aptCache,
        args,
        environment: {'LC_ALL': 'C'},
      ).timeout(_queryTimeout);
      if (result.exitCode != 0) {
        return const {};
      }
      return parseAptCachePolicy(result.stdout.toString());
    } catch (_) {
      return const {};
    }
  }

  // ── cargo 安装 ──────────────────────────────────────────────────────

  Future<ScxUpdateReport> _checkCargo({
    required void Function(String)? onProgress,
  }) async {
    onProgress?.call('正在读取已安装的版本…');
    final listed = await _cargoInstallList();
    // `cargo install --list` 只反映当前用户 CARGO_HOME 下的安装：
    // 读到 scx_* crate 即用户级安装，否则按二进制回退（多为系统级安装）。
    final userLevel = listed.keys.any((name) => name.startsWith('scx_'));
    final installed = userLevel
        ? <String, String>{
            for (final entry in listed.entries)
              if (entry.key.startsWith('scx_')) entry.key: entry.value,
          }
        : await _binaryVersions(cargoCrates);
    onProgress?.call('正在查询 crates.io 最新版本…');
    final names = installed.isNotEmpty
        ? installed.keys.toList()
        : List.of(cargoCrates);
    final latest = await _fetchLatestCrateVersions(names);
    final components = <ScxComponentCheck>[
      for (final name in names)
        buildComponent(
          name: name,
          installed: installed[name],
          latest: latest[name],
        ),
    ];
    return ScxUpdateReport(
      setup: ScxSetupKind.cargo,
      components: components,
      cargoUserLevel: userLevel,
      note: latest.values.every((v) => v == null)
          ? '无法连接 crates.io（含国内镜像），请检查网络后重试。'
          : null,
    );
  }

  /// 是否存在 cargo 安装的迹象：可执行文件存在，或 cargo 记录里有 scx_*。
  ///
  /// 应用自身的 cargo 安装以 `--root /usr` 写入 /usr/bin（dpkg 不认领），
  /// 因此二进制存在但系统源未安装时按 cargo 处理。
  Future<bool> _hasCargoEvidence() async {
    const binaries = <String>[
      ...ScxInstallationService.schedulerNames,
      ...ScxInstallationService.loaderNames,
    ];
    if (ScxInstallationService.hasAnyBinary(
      ScxInstallationService.searchDirs(),
      binaries,
    )) {
      return true;
    }
    final listed = await _cargoInstallList();
    return listed.keys.any((name) => name.startsWith('scx_'));
  }

  /// 用户级 cargo 覆盖更新的固定参数（走 rsproxy.cn 国内镜像）。
  static List<String> cargoForceInstallArgs(Iterable<String> crates) => [
    'install',
    '--force',
    '--config',
    'source.crates-io.replace-with="rsproxy-sparse"',
    '--config',
    'source.rsproxy-sparse.registry="sparse+https://rsproxy.cn/index/"',
    ...crates,
  ];

  /// 以当前用户身份覆盖更新用户的 cargo 安装（`cargo install --force`，
  /// 走国内镜像；无需管理员授权）。
  ///
  /// 用于 [ScxUpdateReport.cargoUserLevel] 为 true（~/.cargo 下的安装）
  /// 的场景；命令输出经 [onLog] 逐行回传。返回 null 表示成功。
  Future<String?> updateViaCargoUserLevel({
    required List<String> crates,
    void Function(String)? onProgress,
    void Function(String)? onLog,
  }) async {
    if (crates.isEmpty) {
      return null;
    }
    final cargo = _findCargo();
    if (cargo == null) {
      return '未找到 cargo，无法覆盖更新';
    }
    onProgress?.call('正在覆盖更新 ${crates.join('、')}…');
    Process process;
    try {
      process = await Process.start(
        cargo,
        cargoForceInstallArgs(crates),
        environment: {'LC_ALL': 'C'},
      );
    } on ProcessException catch (error) {
      return '无法执行 cargo：${error.message}';
    }
    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.trim().isNotEmpty) {
            onLog?.call(line);
          }
        })
        .asFuture<void>();
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.trim().isNotEmpty) {
            onLog?.call(line);
          }
        })
        .asFuture<void>();
    int code;
    try {
      code = await process.exitCode.timeout(_cargoUpdateTimeout);
      await Future.wait([stdoutDone, stderrDone]);
    } on TimeoutException {
      process.kill();
      return 'cargo 覆盖更新超时';
    } catch (error) {
      return 'cargo 覆盖更新失败：$error';
    }
    return code == 0 ? null : 'cargo 覆盖更新失败（退出码 $code）';
  }

  Future<Map<String, String>> _cargoInstallList() async {
    final cargo = _findCargo();
    if (cargo == null) {
      return const {};
    }
    try {
      final result = await Process.run(
        cargo,
        ['install', '--list'],
        environment: {'LC_ALL': 'C'},
      ).timeout(const Duration(seconds: 20));
      if (result.exitCode != 0) {
        return const {};
      }
      return parseCargoInstallList(result.stdout.toString());
    } catch (_) {
      return const {};
    }
  }

  /// 依次从 ~/.cargo/bin 与 PATH 中查找 cargo。
  static String? _findCargo() {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      final path = '$home/.cargo/bin/cargo';
      if (File(path).existsSync()) {
        return path;
      }
    }
    for (final dir in (Platform.environment['PATH'] ?? '').split(':')) {
      if (dir.isEmpty) {
        continue;
      }
      final path = '$dir/cargo';
      if (File(path).existsSync()) {
        return path;
      }
    }
    return null;
  }

  /// 尝试用二进制 `--version` 读取版本（应用自身的 cargo 安装场景）。
  Future<Map<String, String>> _binaryVersions(List<String> names) async {
    final result = <String, String>{};
    for (final name in names) {
      final path = _findBinary(name);
      if (path == null) {
        continue;
      }
      try {
        final run = await Process.run(path, [
          '--version',
        ]).timeout(const Duration(seconds: 5));
        final version = parseBinVersion('${run.stdout}\n${run.stderr}');
        if (version != null) {
          result[name] = version;
        }
      } catch (_) {
        // 二进制不支持 --version 时忽略该组件。
      }
    }
    return result;
  }

  static String? _findBinary(String name) {
    for (final dir in ScxInstallationService.searchDirs()) {
      final path = '$dir/$name';
      if (File(path).existsSync()) {
        return path;
      }
    }
    return null;
  }

  /// 读取 crates.io 最新稳定版本；优先 rsproxy sparse 索引，
  /// 失败后回退官方 API。
  Future<Map<String, String?>> _fetchLatestCrateVersions(
    List<String> names,
  ) async {
    final result = <String, String?>{};
    for (final name in names) {
      result[name] =
          await _fetchFromSparseIndex(name) ?? await _fetchFromCratesIo(name);
    }
    return result;
  }

  Future<String?> _fetchFromSparseIndex(String name) async {
    final text = await _httpGetText(
      Uri.parse('https://rsproxy.cn/index/${sparseIndexPath(name)}'),
    );
    return text == null ? null : parseSparseIndexLatest(text);
  }

  Future<String?> _fetchFromCratesIo(String name) async {
    final text = await _httpGetText(
      Uri.parse('https://crates.io/api/v1/crates/$name'),
    );
    return text == null ? null : parseCratesIoLatest(text);
  }

  Future<String?> _httpGetText(Uri uri) async {
    final client = HttpClient()..connectionTimeout = _httpTimeout;
    try {
      final request = await client.getUrl(uri).timeout(_httpTimeout);
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      final response = await request.close().timeout(_httpTimeout);
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }
      return await response
          .transform(utf8.decoder)
          .join()
          .timeout(_httpTimeout);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> _readDpkgStatus() async {
    try {
      return await File(ScxInstallationService.dpkgStatusPath).readAsString();
    } on FileSystemException {
      return null;
    }
  }

  // ── 解析与比对（纯函数，供测试） ────────────────────────────────────

  static ScxComponentCheck buildComponent({
    required String name,
    String? installed,
    String? latest,
  }) => ScxComponentCheck(
    name: name,
    installedVersion: installed,
    latestVersion: latest,
    state: versionState(installed, latest),
  );

  /// 根据已安装与最新版本判断状态。
  static ScxVersionState versionState(String? installed, String? latest) {
    if (installed == null ||
        latest == null ||
        installed.isEmpty ||
        latest.isEmpty) {
      return ScxVersionState.unknown;
    }
    return compareScxVersions(installed, latest) >= 0
        ? ScxVersionState.upToDate
        : ScxVersionState.updateAvailable;
  }

  /// 比较版本号（兼容 `1.1.4`、`1.1.4-1`、`1:1.1.4~rc1` 等写法）。
  ///
  /// 返回负数表示 [a] 更早，0 相等，正数表示 [a] 更新；数字段按数值比较，
  /// `~` 前缀段（预发布）排在任何对应段之前。
  static int compareScxVersions(String a, String b) {
    final left = _versionParts(a);
    final right = _versionParts(b);
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final x = i < left.length ? left[i] : _VersionPart.zero;
      final y = i < right.length ? right[i] : _VersionPart.zero;
      final cmp = x.compareTo(y);
      if (cmp != 0) {
        return cmp;
      }
    }
    return 0;
  }

  static List<_VersionPart> _versionParts(String version) {
    final body = version.contains(':')
        ? version.substring(version.indexOf(':') + 1)
        : version;
    final parts = <_VersionPart>[];
    for (final match in RegExp(r'(\d+)|([A-Za-z~]+)').allMatches(body)) {
      final digits = match.group(1);
      parts.add(
        digits != null
            ? _VersionPart(int.parse(digits), null)
            : _VersionPart(null, match.group(2)),
      );
    }
    return parts;
  }

  /// 解析 `apt-cache policy`（LC_ALL=C）输出中每个包的候选版本。
  static Map<String, String?> parseAptCachePolicy(String output) {
    final result = <String, String?>{};
    String? current;
    for (final rawLine in output.split('\n')) {
      final line = rawLine.trimRight();
      if (line.isEmpty) {
        continue;
      }
      if (!line.startsWith(' ') && line.endsWith(':')) {
        current = line.substring(0, line.length - 1);
        continue;
      }
      if (current == null) {
        continue;
      }
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('Candidate:')) {
        final value = trimmed.substring('Candidate:'.length).trim();
        result[current] = value == '(none)' ? null : value;
      }
    }
    return result;
  }

  /// 解析 `cargo install --list` 输出中的 crate 及版本（`name v1.2.3:`）。
  static Map<String, String> parseCargoInstallList(String output) {
    final result = <String, String>{};
    final pattern = RegExp(r'^(\S+) v(\S+):$', multiLine: true);
    for (final match in pattern.allMatches(output)) {
      result[match.group(1)!] = match.group(2)!;
    }
    return result;
  }

  /// sparse 索引路径（crate 名均为小写）。
  static String sparseIndexPath(String name) {
    final lower = name.toLowerCase();
    if (lower.length == 1) {
      return '1/$lower';
    }
    if (lower.length == 2) {
      return '2/$lower';
    }
    if (lower.length == 3) {
      return '3/${lower[0]}/$lower';
    }
    return '${lower.substring(0, 2)}/${lower.substring(2, 4)}/$lower';
  }

  /// sparse 索引内容（每行一个版本的 JSON）里的最高非 yank 版本。
  static String? parseSparseIndexLatest(String indexText) {
    String? best;
    for (final line in indexText.split('\n')) {
      if (line.trim().isEmpty) {
        continue;
      }
      try {
        final data = jsonDecode(line) as Map<String, dynamic>;
        if (data['yanked'] == true) {
          continue;
        }
        final version = data['vers'] as String?;
        if (version == null) {
          continue;
        }
        if (best == null || compareScxVersions(version, best) > 0) {
          best = version;
        }
      } catch (_) {
        // 忽略无法解析的行。
      }
    }
    return best;
  }

  /// crates.io API 响应里的稳定版最新版本。
  static String? parseCratesIoLatest(String jsonText) {
    try {
      final data = jsonDecode(jsonText) as Map<String, dynamic>;
      final crate = data['crate'] as Map<String, dynamic>?;
      return (crate?['max_stable_version'] as String?) ??
          (crate?['newest_version'] as String?);
    } catch (_) {
      return null;
    }
  }

  /// 从 `--version` 输出中提取形如 `x.y.z` 的版本号。
  static String? parseBinVersion(String output) =>
      RegExp(r'(\d+\.\d+\.\d+)').firstMatch(output)?.group(1);
}

/// 版本号中的一段：数字段或字母段（`~rc` 等预发布前缀）。
class _VersionPart implements Comparable<_VersionPart> {
  const _VersionPart(this.number, this.text);

  final int? number;
  final String? text;

  static const zero = _VersionPart(0, null);

  @override
  int compareTo(_VersionPart other) {
    final a = number;
    final b = other.number;
    if (a != null && b != null) {
      return a.compareTo(b);
    }
    if (a != null) {
      // 数字段排在字母段之后；`~` 前缀段最小。
      return other.text!.startsWith('~') ? 1 : -1;
    }
    if (b != null) {
      return text!.startsWith('~') ? -1 : 1;
    }
    return text!.compareTo(other.text!);
  }
}
