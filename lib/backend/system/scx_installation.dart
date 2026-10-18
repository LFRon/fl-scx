import 'dart:async';
import 'dart:io';

import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

import 'privileged_helper.dart';
import 'scx_loader_files.dart';

/// scx / scx-loader 的安装方式。
enum ScxInstallMethod {
  /// 从 Better Deepin REPO 软件源安装（仅 deepin 且已启用该源时可用）。
  apt,

  /// 经 cargo 编译安装（crates.io，走国内镜像加速）。
  cargo,
}

/// scx / scx-loader 的安装探测与安装流程。
///
/// 探测用于驱动统一的安装状态开关（[ScxAppState.scxInstalled]）；
/// 安装流程的决策（Rust 版本比较、步骤编排、要写入的系统文件内容）
/// 都在这里完成，特权辅助进程只负责执行白名单内的固定命令。
class ScxInstallationService {
  ScxInstallationService({PrivilegedHelper? helper})
    : _helper = helper ?? PrivilegedHelper();

  /// 与 scx_loader 上报的支持列表一致的调度器二进制名。
  static const schedulerNames = <String>[
    'scx_beerland',
    'scx_bpfland',
    'scx_cake',
    'scx_cosmos',
    'scx_flash',
    'scx_flow',
    'scx_forge',
    'scx_lavd',
    'scx_mlfq',
    'scx_pandemonium',
    'scx_p2dq',
    'scx_tickless',
    'scx_rustland',
    'scx_rusty',
  ];

  /// scx-loader 侧可执行文件（守护进程与命令行客户端）。
  static const loaderNames = <String>['scx_loader', 'scxctl'];

  /// 二进制候选目录（与 ScxControlService 的查找位置保持一致）。
  static const binaryDirs = <String>['/usr/bin', '/usr/local/bin'];

  /// apt 安装的软件包（Better Deepin REPO 中的实际包名）。
  static const aptPackages = <String>['scx-scheds', 'scx-loader'];

  /// dpkg 状态库路径（世界可读，无需授权即可核验安装结果）。
  static const dpkgStatusPath = '/var/lib/dpkg/status';

  /// cargo 安装要求的 rustc 最低版本。
  static const minRustcMajor = 1;
  static const minRustcMinor = 95;

  final PrivilegedHelper _helper;

  /// 二进制查找目录（含用户级 cargo 安装位置）。
  static List<String> searchDirs() {
    final dirs = <String>[...binaryDirs];
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      dirs.add('$home/.cargo/bin');
    }
    return dirs;
  }

  /// [dirs] 中是否存在 [names] 里的任一可执行文件。
  static bool hasAnyBinary(Iterable<String> dirs, Iterable<String> names) {
    for (final dir in dirs) {
      for (final name in names) {
        if (File('$dir/$name').existsSync()) {
          return true;
        }
      }
    }
    return false;
  }

  /// 统一判定 scx 运行环境是否已安装：
  /// scx-loader 可用（D-Bus 已响应或可执行文件存在）且至少有一个调度器。
  static bool isInstalled({
    required bool daemonAvailable,
    Iterable<String>? dirs,
  }) {
    final search = dirs ?? searchDirs();
    final loader = daemonAvailable || hasAnyBinary(search, loaderNames);
    return loader && hasAnyBinary(search, schedulerNames);
  }

  /// [dirs] 中是否 [names] 全部存在（用于核验安装产物）。
  static bool allBinariesPresent(Iterable<String> dirs, Iterable<String> names) {
    for (final name in names) {
      var found = false;
      for (final dir in dirs) {
        if (File('$dir/$name').existsSync()) {
          found = true;
          break;
        }
      }
      if (!found) {
        return false;
      }
    }
    return true;
  }

  /// 判断 dpkg 状态文本中 [package] 是否已正确安装
  /// （`Status: install ok installed`）。
  static bool dpkgPackageInstalled(String dpkgStatusText, String package) {
    for (final block in dpkgStatusText.split('\n\n')) {
      String? name;
      var installed = false;
      for (final line in block.split('\n')) {
        if (line.startsWith('Package: ')) {
          name = line.substring('Package: '.length).trim();
        } else if (line.startsWith('Status: ')) {
          installed =
              line.substring('Status: '.length).trim() == 'install ok installed';
        }
      }
      if (name == package) {
        return installed;
      }
    }
    return false;
  }

  /// 核验 apt 软件包是否都已安装（命令通道中断时以实际状态为准）。
  static Future<bool> aptPackagesInstalled() async {
    try {
      final text = await File(dpkgStatusPath).readAsString();
      return aptPackages.every((pkg) => dpkgPackageInstalled(text, pkg));
    } on FileSystemException {
      return false;
    }
  }

  /// 判断 dpkg 状态文本中 [package] 已安装时的版本号；
  /// 未安装或缺少 Version 字段时返回 null。
  static String? dpkgPackageVersion(String dpkgStatusText, String package) {
    for (final block in dpkgStatusText.split('\n\n')) {
      String? name;
      String? status;
      String? version;
      for (final line in block.split('\n')) {
        if (line.startsWith('Package: ')) {
          name = line.substring('Package: '.length).trim();
        } else if (line.startsWith('Status: ')) {
          status = line.substring('Status: '.length).trim();
        } else if (line.startsWith('Version: ')) {
          version = line.substring('Version: '.length).trim();
        }
      }
      if (name == package) {
        return status == 'install ok installed' ? version : null;
      }
    }
    return null;
  }

  /// rustc 版本文本（如 `rustc 1.95.0 (…)`）是否满足最低版本要求。
  static bool rustcSatisfies(String versionText) {
    final match = RegExp(r'rustc (\d+)\.(\d+)').firstMatch(versionText);
    if (match == null) {
      return false;
    }
    final major = int.parse(match.group(1)!);
    final minor = int.parse(match.group(2)!);
    return major > minRustcMajor ||
        (major == minRustcMajor && minor >= minRustcMinor);
  }

  /// 安装前的网络连通性检查；返回 null 表示网络可用。
  Future<String?> _ensureNetwork({void Function(String)? onProgress}) async {
    onProgress?.call('正在检查网络连接…');
    try {
      final connected = await InternetConnection().hasInternetAccess.timeout(
        const Duration(seconds: 12),
      );
      if (!connected) {
        return '网络连接不可用：安装需要联网，请检查网络后重试';
      }
      return null;
    } on TimeoutException {
      return '网络连接检查超时：安装需要联网，请检查网络后重试';
    } catch (_) {
      return '网络连接检查失败：安装需要联网，请检查网络后重试';
    }
  }

  /// 从 Better Deepin REPO 安装 scx-scheds 与 scx-loader。
  ///
  /// 先检查网络连通性，再执行 `apt update` 并安装两个软件包；命令输出
  /// 通过 [onLog] 逐行回传（安装日志对话框），阶段文本通过 [onProgress]。
  /// 返回 null 表示成功。
  Future<String?> installViaApt({
    void Function(String)? onProgress,
    void Function(String)? onLog,
  }) async {
    final networkError = await _ensureNetwork(onProgress: onProgress);
    if (networkError != null) {
      return networkError;
    }
    onProgress?.call('正在更新软件源（apt update）…');
    final update = await _helper.aptUpdate(onLog: onLog);
    if (!update.isOk) {
      // 命令通道可能中断（例如授权会话被中断/结束）：以 dpkg 实际状态为准。
      if (await aptPackagesInstalled()) {
        onLog?.call('软件源更新未收到成功确认，但软件包已正确安装（以 dpkg 状态为准）。');
        return null;
      }
      return update.message ?? 'apt update 失败';
    }
    onProgress?.call('正在安装 ${aptPackages.join(' 与 ')}…');
    final install = await _helper.aptInstall(
      packages: aptPackages,
      onLog: onLog,
    );
    if (!install.isOk) {
      if (await aptPackagesInstalled()) {
        onLog?.call('安装命令未收到成功确认，但软件包已正确安装（以 dpkg 状态为准）。');
        return null;
      }
      return install.message ?? '软件包安装失败';
    }
    return null;
  }

  /// 经 cargo 编译安装 scx（scx_lavd）与 scx-loader（scx_loader、scxctl）。
  ///
  /// Rust 编译器缺失或低于 1.95 时，先通过国内镜像（rsproxy.cn）
  /// 安装/更新 Rust 工具链；随后依次编译安装 scx-loader 与调度器，
  /// 最后写入 systemd / D-Bus / polkit / 示例配置并启用服务。
  /// 命令输出通过 [onLog] 逐行回传，返回 null 表示成功。
  Future<String?> installViaCargo({
    void Function(String)? onProgress,
    void Function(String)? onLog,
  }) async {
    final networkError = await _ensureNetwork(onProgress: onProgress);
    if (networkError != null) {
      return networkError;
    }
    onProgress?.call('正在检查 Rust 编译器…');
    final version = await _helper.rustcVersion();
    if (!version.isOk || !rustcSatisfies(version.message ?? '')) {
      onProgress?.call('Rust 编译器缺失或低于 1.95，正在通过国内镜像安装…');
      final rustup = await _helper.installRustToolchain(onLog: onLog);
      if (!rustup.isOk) {
        // 命令通道可能中断：回读一次版本，确认工具链是否实际已就绪。
        final recheck = await _helper.rustcVersion();
        if (!recheck.isOk || !rustcSatisfies(recheck.message ?? '')) {
          return rustup.message ?? 'Rust 工具链安装失败';
        }
        onLog?.call('安装命令未收到成功确认，但已检测到可用的 Rust 编译器。');
      }
    }

    onProgress?.call('正在编译安装 scx-loader（scx_loader、scxctl）…');
    final loader = await _helper.cargoInstallScxLoader(onLog: onLog);
    if (!loader.isOk) {
      if (!allBinariesPresent(searchDirs(), loaderNames)) {
        return loader.message ?? 'scx-loader 安装失败';
      }
      onLog?.call('安装命令未收到成功确认，但已检测到 scx_loader 与 scxctl。');
    }

    onProgress?.call('正在编译安装 scx_lavd 调度器…');
    final lavd = await _helper.cargoInstallScxLavd(onLog: onLog);
    if (!lavd.isOk) {
      if (!hasAnyBinary(searchDirs(), schedulerNames)) {
        return lavd.message ?? 'scx_lavd 调度器安装失败';
      }
      onLog?.call('安装命令未收到成功确认，但已检测到 scx 调度器二进制。');
    }

    onProgress?.call('正在写入 systemd / D-Bus / polkit 配置…');
    for (final file in scxLoaderSystemFiles) {
      final write = await _helper.writeConfigFile(
        path: file.path,
        content: file.content,
      );
      if (!write.isOk) {
        return '写入 ${file.path} 失败：${write.message ?? '未知错误'}';
      }
    }
    final reload = await _helper.daemonReload();
    if (!reload.isOk) {
      return reload.message ?? 'systemctl daemon-reload 失败';
    }
    final enable = await _helper.setServiceEnabled(enabled: true);
    if (!enable.isOk) {
      return enable.message ?? '启用 scx_loader 服务失败';
    }
    return null;
  }
}
