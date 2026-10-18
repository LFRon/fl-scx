import 'package:test/test.dart';

import 'dart:io';

import 'package:fl_scx/backend/config/loader_config.dart';
import 'package:fl_scx/backend/models/mode_args.dart';
import 'package:fl_scx/backend/models/sched_mode.dart';
import 'package:fl_scx/backend/models/scx_snapshot.dart';
import 'package:fl_scx/backend/system/distro_info.dart';
import 'package:fl_scx/backend/system/privileged_helper.dart';
import 'package:fl_scx/backend/system/scx_control_service.dart';
import 'package:fl_scx/backend/system/scx_installation.dart';
import 'package:fl_scx/backend/system/scx_update_service.dart';
import 'package:fl_scx/backend/system/systemd_controller.dart';

void main() {
  group('SchedMode', () {
    test('fromRaw 映射 D-Bus 数值', () {
      expect(SchedMode.fromRaw(0), SchedMode.auto);
      expect(SchedMode.fromRaw(1), SchedMode.gaming);
      expect(SchedMode.fromRaw(2), SchedMode.powerSave);
      expect(SchedMode.fromRaw(3), SchedMode.lowLatency);
      expect(SchedMode.fromRaw(4), SchedMode.server);
      expect(SchedMode.fromRaw(99), SchedMode.auto);
    });

    test('fromTomlName 解析配置值且不区分大小写', () {
      expect(SchedMode.fromTomlName('Auto'), SchedMode.auto);
      expect(SchedMode.fromTomlName('powersave'), SchedMode.powerSave);
      expect(SchedMode.fromTomlName('LowLatency'), SchedMode.lowLatency);
      expect(SchedMode.fromTomlName('Server'), SchedMode.server);
      expect(SchedMode.fromTomlName('unknown'), SchedMode.auto);
    });

    test('cliName 与 scxctl 取值一致', () {
      expect(SchedMode.auto.cliName, 'auto');
      expect(SchedMode.gaming.cliName, 'gaming');
      expect(SchedMode.powerSave.cliName, 'powersave');
      expect(SchedMode.lowLatency.cliName, 'lowlatency');
      expect(SchedMode.server.cliName, 'server');
    });
  });

  group('ScxControlService.buildArguments', () {
    test('运行时使用 switch 并传递 --mode', () {
      final argv = ScxControlService.buildArguments(
        start: false,
        scheduler: 'scx_lavd',
        mode: SchedMode.gaming,
      );
      expect(argv, ['switch', '--sched', 'scx_lavd', '--mode', 'gaming']);
    });

    test('停止状态使用 start（scxctl 的 switch 在无运行调度器时会失败）', () {
      final argv = ScxControlService.buildArguments(
        start: true,
        scheduler: 'scx_lavd',
        mode: SchedMode.auto,
      );
      expect(argv, ['start', '--sched', 'scx_lavd', '--mode', 'auto']);
    });

    test('自定义参数使用内联 --args=... 形式（避免被当作选项）', () {
      final argv = ScxControlService.buildArguments(
        start: false,
        scheduler: 'scx_lavd',
        mode: SchedMode.auto,
        args: ['-m', 'performance', '-w'],
      );
      expect(argv, [
        'switch',
        '--sched',
        'scx_lavd',
        '--args=-m,performance,-w',
      ]);
      expect(argv, isNot(contains('--mode')));
    });
  });

  group('调度器名称', () {
    test('shortSchedulerName 去除 scx_ 前缀', () {
      expect(shortSchedulerName('scx_lavd'), 'lavd');
      expect(shortSchedulerName('lavd'), 'lavd');
    });

    test('fullSchedulerName 补全 scx_ 前缀', () {
      expect(fullSchedulerName('lavd'), 'scx_lavd');
      expect(fullSchedulerName('scx_lavd'), 'scx_lavd');
    });
  });

  group('内核 ops 名称', () {
    test('shortKernelOpsName 处理版本三元组/完整名/裸名', () {
      expect(
        shortKernelOpsName('lavd_1.1.3_x86_64_unknown_linux_gnu'),
        'lavd',
      );
      expect(shortKernelOpsName('scx_lavd'), 'lavd');
      expect(shortKernelOpsName('lavd'), 'lavd');
      expect(shortKernelOpsName('lavd-1.1.3'), 'lavd');
      expect(shortKernelOpsName(''), '');
    });

    test('kernelOpsMatches 模糊匹配各格式', () {
      expect(
        kernelOpsMatches('lavd_1.1.3_x86_64_unknown_linux_gnu', 'scx_lavd'),
        isTrue,
      );
      expect(kernelOpsMatches('scx_lavd', 'scx_lavd'), isTrue);
      expect(kernelOpsMatches('lavd', 'scx_lavd'), isTrue);
      expect(kernelOpsMatches('scx-lavd-1.1.3', 'scx_lavd'), isTrue);
      expect(kernelOpsMatches('lavd1.1.3', 'scx_lavd'), isTrue);
      expect(
        kernelOpsMatches('bpfland_1.1.3_x86_64', 'scx_lavd'),
        isFalse,
      );
      expect(kernelOpsMatches('', 'scx_lavd'), isFalse);
      expect(kernelOpsMatches('lavdx_1.1.3', 'scx_lavd'), isFalse);
      expect(kernelOpsMatches('lavd_1.1.3', 'scx_lavdx'), isFalse);
    });
  });

  group('ScxSnapshot.schedulerRunning', () {
    ScxSnapshot snapshotWith({
      bool daemonAvailable = true,
      String current = 'scx_lavd',
      String kernelState = 'enabled',
      String kernelOps = 'lavd_1.1.3_x86_64_unknown_linux_gnu',
    }) => ScxSnapshot(
      daemonAvailable: daemonAvailable,
      currentScheduler: current,
      currentMode: SchedMode.auto,
      currentArgs: const ['--abc'],
      supportedSchedulers: const ['scx_lavd'],
      defaultScheduler: 'scx_lavd',
      defaultMode: SchedMode.auto,
      kernelState: kernelState,
      kernelOps: kernelOps,
      service: SystemServiceState.unknown,
      configPath: '/etc/scx_loader/config.toml',
    );

    test('内核 ops 匹配时视为运行中', () {
      expect(snapshotWith().schedulerRunning, isTrue);
    });

    test('内核 ops 为空时不算运行中（守护进程乐观属性不回滚）', () {
      expect(snapshotWith(kernelOps: '').schedulerRunning, isFalse);
    });

    test('内核状态不可读时退回守护进程信息', () {
      expect(
        snapshotWith(kernelState: '', kernelOps: '').schedulerRunning,
        isTrue,
      );
    });

    test('守护进程不可用或未运行时为 false', () {
      expect(snapshotWith(daemonAvailable: false).schedulerRunning, isFalse);
      expect(snapshotWith(current: 'unknown').schedulerRunning, isFalse);
    });
  });

  group('LoaderConfig.applyDefaults', () {
    final config = LoaderConfig();

    test('在空配置上生成完整的默认块', () {
      final text = config.applyDefaults(
        '',
        scheduler: 'scx_lavd',
        mode: SchedMode.auto,
      );
      expect(text, contains('default_sched = "scx_lavd"'));
      expect(text, contains('default_mode = "Auto"'));
    });

    test('覆盖已有默认值并保留其余内容', () {
      const source = '''
default_sched = "scx_rusty"
default_mode = "Gaming"

[scheds.scx_lavd]
auto_mode = ["--autopilot"]
''';
      final text = config.applyDefaults(
        source,
        scheduler: 'scx_lavd',
        mode: SchedMode.lowLatency,
      );
      expect(text, contains('default_sched = "scx_lavd"'));
      expect(text, contains('default_mode = "LowLatency"'));
      expect(text, isNot(contains('scx_rusty')));
      expect(text, contains('[scheds.scx_lavd]'));
      expect(text, contains('auto_mode = ["--autopilot"]'));
    });

    test('解析回读默认值', () async {
      const source = '''
default_sched = "scx_bpfland"
default_mode = "Server"
''';
      final text = config.applyDefaults(
        source,
        scheduler: 'scx_bpfland',
        mode: SchedMode.server,
      );
      expect(text, contains('default_sched = "scx_bpfland"'));
      expect(text, contains('default_mode = "Server"'));
    });

    test('重复应用不会累积管理注释与默认行', () {
      const source = '''
# 由 fl_scx 写入：scx_loader 启动时自动应用的调度器与模式
default_sched = "scx_lavd"
default_mode = "Auto"

# 原有内容
[scheds.scx_lavd]
auto_mode = ["--autopilot"]
''';
      final text = config.applyDefaults(
        source,
        scheduler: 'scx_cosmos',
        mode: SchedMode.gaming,
      );
      expect('# 由 fl_scx 写入'.allMatches(text).length, 1);
      expect(text, contains('default_sched = "scx_cosmos"'));
      expect(text, contains('default_mode = "Gaming"'));
      expect(text, isNot(contains('scx_lavd"')));
      expect(text, contains('[scheds.scx_lavd]'));
      expect(text, contains('auto_mode = ["--autopilot"]'));
    });

    test('连续两次应用结果稳定（幂等）', () {
      final once = config.applyDefaults(
        '',
        scheduler: 'scx_lavd',
        mode: SchedMode.auto,
      );
      final twice = config.applyDefaults(
        once,
        scheduler: 'scx_lavd',
        mode: SchedMode.auto,
      );
      expect(twice, once);
    });

    test('五种模式名称与 scx_loader 配置格式一致', () {
      for (final mode in SchedMode.values) {
        final text = config.applyDefaults(
          '',
          scheduler: 'scx_lavd',
          mode: mode,
        );
        expect(text, contains('default_mode = "${mode.tomlName}"'));
      }
    });

    test('configKey 与 scx_loader 配置键名一致', () {
      expect(SchedMode.auto.configKey, 'auto_mode');
      expect(SchedMode.gaming.configKey, 'gaming_mode');
      expect(SchedMode.powerSave.configKey, 'powersave_mode');
      expect(SchedMode.lowLatency.configKey, 'lowlatency_mode');
      expect(SchedMode.server.configKey, 'server_mode');
    });

    test('自定义参数会写入所选模式的配置数组且保留其它模式', () {
      const source = '''
default_sched = "scx_lavd"
default_mode = "Auto"

[scheds.scx_lavd]
auto_mode = ["--autopilot"]
''';
      final text = config.applyDefaults(
        source,
        scheduler: 'scx_lavd',
        mode: SchedMode.gaming,
        args: ['-m', 'performance', '-w'],
      );
      expect(text, contains('default_mode = "Gaming"'));
      expect(text, contains('gaming_mode = ["-m", "performance", "-w"]'));
      expect(text, contains('auto_mode = ["--autopilot"]'));
      expect('gaming_mode'.allMatches(text).length, 1);
    });

    test('目标调度器缺少 scheds 段时自动追加新段', () {
      final text = config.applyDefaults(
        '# 仅有注释',
        scheduler: 'scx_cosmos',
        mode: SchedMode.auto,
        args: ['-s', '700'],
      );
      expect(text, contains('[scheds.scx_cosmos]'));
      expect(text, contains('auto_mode = ["-s", "700"]'));
      expect(text, contains('default_sched = "scx_cosmos"'));
    });

    test('已有模式参数会被更新且不重复', () {
      const source = '''
[scheds.scx_lavd]
gaming_mode = ["--old"]
auto_mode = ["--autopilot"]
''';
      final text = config.applyDefaults(
        source,
        scheduler: 'scx_lavd',
        mode: SchedMode.gaming,
        args: ['--new'],
      );
      expect(text, contains('gaming_mode = ["--new"]'));
      expect('gaming_mode'.allMatches(text).length, 1);
      expect(text, contains('auto_mode = ["--autopilot"]'));
    });

    test('参数中的引号与反斜杠会被转义', () {
      final text = config.applyDefaults(
        '',
        scheduler: 'scx_lavd',
        mode: SchedMode.auto,
        args: ['a"b', r'c\d'],
      );
      expect(text, contains(r'auto_mode = ["a\"b", "c\\d"]'));
    });
  });

  group('DistroInfo', () {
    test('parseOsReleaseId 解析并去除引号', () {
      expect(DistroInfo.parseOsReleaseId('ID=deepin\nNAME=Deepin\n'), 'deepin');
      expect(DistroInfo.parseOsReleaseId('ID="deepin"\n'), 'deepin');
      expect(DistroInfo.parseOsReleaseId("ID='deepin'\n"), 'deepin');
      expect(DistroInfo.parseOsReleaseId('NAME=Deepin\n'), isNull);
    });

    test('containsBetterDeepinRepo 匹配两个已知源', () {
      expect(
        DistroInfo.containsBetterDeepinRepo(
          'deb [trusted=yes] '
          'https://obsci.odata.cc/Better-Deepin-REPO/Deepin_25/ ./',
        ),
        isTrue,
      );
      expect(
        DistroInfo.containsBetterDeepinRepo(
          'deb https://repo.odata.cc/deepin25/ Deepin_25 main',
        ),
        isTrue,
      );
      expect(
        DistroInfo.containsBetterDeepinRepo(
          'deb https://deb.debian.org/debian bookworm main',
        ),
        isFalse,
      );
    });

    test('aptCheckSupportedForId 仅支持 Ubuntu/Debian/deepin', () {
      expect(DistroInfo.aptCheckSupportedForId('deepin'), isTrue);
      expect(DistroInfo.aptCheckSupportedForId('ubuntu'), isTrue);
      expect(DistroInfo.aptCheckSupportedForId('Debian'), isTrue);
      expect(DistroInfo.aptCheckSupportedForId('fedora'), isFalse);
      expect(DistroInfo.aptCheckSupportedForId('arch'), isFalse);
      expect(DistroInfo.aptCheckSupportedForId('linuxmint'), isFalse);
      expect(DistroInfo.aptCheckSupportedForId(''), isFalse);
      expect(DistroInfo.aptCheckSupportedForId(null), isFalse);
    });
  });

  group('ScxInstallationService', () {
    test('rustcSatisfies 版本比较以 1.95 为界', () {
      expect(
        ScxInstallationService.rustcSatisfies(
          'rustc 1.95.0 (59807616e 2026-06-01)',
        ),
        isTrue,
      );
      expect(ScxInstallationService.rustcSatisfies('rustc 1.96.0-nightly'), isTrue);
      expect(ScxInstallationService.rustcSatisfies('rustc 2.0.0'), isTrue);
      expect(
        ScxInstallationService.rustcSatisfies(
          'rustc 1.94.1 (e408947bf 2026-01-01)',
        ),
        isFalse,
      );
      expect(ScxInstallationService.rustcSatisfies('未找到'), isFalse);
    });

    test('isInstalled 需要 scx-loader 与至少一个调度器', () async {
      final dir = await Directory.systemTemp.createTemp('fl_scx_install_test');
      addTearDown(() => dir.delete(recursive: true));
      final bin = Directory('${dir.path}/bin')..createSync();
      final dirs = [bin.path];

      // 什么都没有：未安装。
      expect(
        ScxInstallationService.isInstalled(daemonAvailable: false, dirs: dirs),
        isFalse,
      );
      // 只有 scxctl：仍视为未安装（缺少调度器）。
      File('${bin.path}/scxctl').writeAsStringSync('');
      expect(
        ScxInstallationService.isInstalled(daemonAvailable: false, dirs: dirs),
        isFalse,
      );
      // 有调度器二进制但 D-Bus 不可用：已安装（文件存在）。
      File('${bin.path}/scx_lavd').writeAsStringSync('');
      expect(
        ScxInstallationService.isInstalled(daemonAvailable: false, dirs: dirs),
        isTrue,
      );
      // D-Bus 可用时即使目录为空也视为已安装 loader 侧（需有调度器）。
      final empty = Directory('${dir.path}/empty')..createSync();
      expect(
        ScxInstallationService.isInstalled(
          daemonAvailable: true,
          dirs: [empty.path],
        ),
        isFalse,
      );
    });
  });

  group('ProtocolLineSplitter', () {
    test('仅按 \\n 断行：dpkg 的 \\r 进度不会被拆成多行', () async {
      final lines = await Stream.fromIterable([
        'LOG (正在读取数据库 ... 5%\r',
        '(正在读取数据库 ... 10%\r\n',
        'OK\n',
      ]).transform(const ProtocolLineSplitter()).toList();
      expect(lines, [
        'LOG (正在读取数据库 ... 5%\r(正在读取数据库 ... 10%',
        'OK',
      ]);
    });

    test('跨块拼行、CRLF 去除与末尾残留输出', () async {
      final lines = await Stream.fromIterable([
        'READY\nLO',
        'G hi\r\nOK',
      ]).transform(const ProtocolLineSplitter()).toList();
      expect(lines, ['READY', 'LOG hi', 'OK']);

      final tail = await Stream.fromIterable([
        'LOG tail',
      ]).transform(const ProtocolLineSplitter()).toList();
      expect(tail, ['LOG tail']);
    });
  });

  group('ScxInstallationService 安装核验', () {
    test('dpkgPackageInstalled 解析安装状态', () {
      const status = '''
Package: scx-scheds
Status: install ok installed
Version: 1.1.3-2

Package: scx-loader
Status: deinstall ok config-files
Version: 1.1.3-1

Package: other
Status: install ok installed
''';
      expect(
        ScxInstallationService.dpkgPackageInstalled(status, 'scx-scheds'),
        isTrue,
      );
      expect(
        ScxInstallationService.dpkgPackageInstalled(status, 'scx-loader'),
        isFalse,
      );
      expect(
        ScxInstallationService.dpkgPackageInstalled(status, 'other'),
        isTrue,
      );
      expect(
        ScxInstallationService.dpkgPackageInstalled(status, 'missing'),
        isFalse,
      );
    });

    test('allBinariesPresent 要求全部存在', () async {
      final dir = await Directory.systemTemp.createTemp('fl_scx_bin_test');
      addTearDown(() => dir.delete(recursive: true));
      File('${dir.path}/scxctl').writeAsStringSync('');
      expect(
        ScxInstallationService.allBinariesPresent([dir.path], ['scxctl']),
        isTrue,
      );
      expect(
        ScxInstallationService.allBinariesPresent([
          dir.path,
        ], ['scxctl', 'scx_loader']),
        isFalse,
      );
      File('${dir.path}/scx_loader').writeAsStringSync('');
      expect(
        ScxInstallationService.allBinariesPresent([
          dir.path,
        ], ['scxctl', 'scx_loader']),
        isTrue,
      );
    });
  });

  group('SystemdController', () {
    test('parseShowOutput 解析 systemctl show 输出', () {
      final state = SystemdController.parseShowOutput(
        'ActiveState=active\nUnitFileState=enabled\n',
      );
      expect(state.active, isTrue);
      expect(state.enabled, isTrue);
    });

    test('parseShowOutput 未安装/未运行单元时均为 false', () {
      final state = SystemdController.parseShowOutput(
        'ActiveState=inactive\nUnitFileState=\n',
      );
      expect(state.active, isFalse);
      expect(state.enabled, isFalse);
    });

    test('parseShowOutput 忽略空行与其它属性', () {
      final state = SystemdController.parseShowOutput(
        '\nLoadState=loaded\nActiveState=failed\nUnitFileState=disabled\n',
      );
      expect(state.active, isFalse);
      expect(state.enabled, isFalse);
    });
  });

  group('ScxUpdateService 更新检查', () {
    const dpkgStatus = '''
Package: scx-scheds
Status: install ok installed
Version: 1.1.3-2

Package: scx-loader
Status: deinstall ok config-files
Version: 1.1.3-1

Package: other
Status: install ok installed
''';

    test('resolveSetup 系统源优先，再看 cargo，否则未知', () {
      expect(
        ScxUpdateService.resolveSetup(
          repoPackagesInstalled: true,
          cargoEvidence: true,
        ),
        ScxSetupKind.systemRepo,
      );
      expect(
        ScxUpdateService.resolveSetup(
          repoPackagesInstalled: false,
          cargoEvidence: true,
        ),
        ScxSetupKind.cargo,
      );
      expect(
        ScxUpdateService.resolveSetup(
          repoPackagesInstalled: false,
          cargoEvidence: false,
        ),
        ScxSetupKind.unknown,
      );
    });

    test('cargoForceInstallArgs 走 rsproxy 镜像强制覆盖', () {
      final args = ScxUpdateService.cargoForceInstallArgs([
        'scx_loader',
        'scxctl',
      ]);
      expect(args.take(2), ['install', '--force']);
      expect(args, contains('source.crates-io.replace-with="rsproxy-sparse"'));
      expect(
        args,
        contains(
          'source.rsproxy-sparse.registry='
          '"sparse+https://rsproxy.cn/index/"',
        ),
      );
      expect(args.sublist(args.length - 2), ['scx_loader', 'scxctl']);
    });

    test('hasUpdate 反映组件状态', () {
      const outdated = ScxUpdateReport(
        setup: ScxSetupKind.cargo,
        components: [
          ScxComponentCheck(
            name: 'scx_loader',
            installedVersion: '1.1.3',
            latestVersion: '1.1.4',
            state: ScxVersionState.updateAvailable,
          ),
        ],
      );
      const current = ScxUpdateReport(
        setup: ScxSetupKind.systemRepo,
        components: [
          ScxComponentCheck(
            name: 'scx-scheds',
            installedVersion: '1.1.4-1',
            latestVersion: '1.1.4-1',
            state: ScxVersionState.upToDate,
          ),
        ],
      );
      expect(outdated.hasUpdate, isTrue);
      expect(outdated.cargoUserLevel, isFalse);
      expect(current.hasUpdate, isFalse);
    });

    test('dpkgPackageVersion 读取已安装版本', () {
      expect(
        ScxInstallationService.dpkgPackageVersion(dpkgStatus, 'scx-scheds'),
        '1.1.3-2',
      );
      expect(
        ScxInstallationService.dpkgPackageVersion(dpkgStatus, 'scx-loader'),
        isNull,
      );
      expect(
        ScxInstallationService.dpkgPackageVersion(dpkgStatus, 'missing'),
        isNull,
      );
    });

    test('compareScxVersions 兼容打包版本与 crate 版本', () {
      expect(
        ScxUpdateService.compareScxVersions('1.1.4-1', '1.1.4'),
        greaterThan(0),
      );
      expect(
        ScxUpdateService.compareScxVersions('1.1.4', '1.1.4-1'),
        lessThan(0),
      );
      expect(ScxUpdateService.compareScxVersions('1.1.4', '1.1.4'), 0);
      expect(
        ScxUpdateService.compareScxVersions('1.1.3', '1.1.4'),
        lessThan(0),
      );
      expect(
        ScxUpdateService.compareScxVersions('1.10.0', '1.9.9'),
        greaterThan(0),
      );
      expect(ScxUpdateService.compareScxVersions('1:1.1.4', '1.1.4'), 0);
      expect(
        ScxUpdateService.compareScxVersions('1.1.4~rc1', '1.1.4'),
        lessThan(0),
      );
      expect(ScxUpdateService.compareScxVersions('1.1', '1.1.0'), 0);
    });

    test('versionState 判定可更新/已是最新/未知', () {
      expect(
        ScxUpdateService.versionState('1.1.3-1', '1.1.4-1'),
        ScxVersionState.updateAvailable,
      );
      expect(
        ScxUpdateService.versionState('1.1.4-1', '1.1.4-1'),
        ScxVersionState.upToDate,
      );
      expect(
        ScxUpdateService.versionState('1.1.4', '1.1.3'),
        ScxVersionState.upToDate,
      );
      expect(
        ScxUpdateService.versionState(null, '1.1.4'),
        ScxVersionState.unknown,
      );
      expect(
        ScxUpdateService.versionState('1.1.4', null),
        ScxVersionState.unknown,
      );
    });

    test('parseAptCachePolicy 解析候选项与 (none)', () {
      const output = '''
scx-scheds:
  Installed: 1.1.4-1
  Candidate: 1.1.4-1
  Version table:
 *** 1.1.4-1 999
        999 https://example.com/repo Packages
        100 /var/lib/dpkg/status
scx-loader:
  Installed: (none)
  Candidate: (none)
  Version table:
''';
      final candidates = ScxUpdateService.parseAptCachePolicy(output);
      expect(candidates['scx-scheds'], '1.1.4-1');
      expect(candidates['scx-loader'], isNull);
    });

    test('parseCargoInstallList 解析 crate 与版本', () {
      const output = '''
scx_loader v1.1.3:
    scx_loader
scx_lavd v1.1.4:
    scx_lavd
ripgrep v14.1.1:
    rg
''';
      final versions = ScxUpdateService.parseCargoInstallList(output);
      expect(versions['scx_loader'], '1.1.3');
      expect(versions['scx_lavd'], '1.1.4');
      expect(versions['ripgrep'], '14.1.1');
    });

    test('sparseIndexPath 按名字长度生成索引路径', () {
      expect(
        ScxUpdateService.sparseIndexPath('scx_loader'),
        'sc/x_/scx_loader',
      );
      expect(ScxUpdateService.sparseIndexPath('scxlavd'), 'sc/xl/scxlavd');
      expect(ScxUpdateService.sparseIndexPath('a'), '1/a');
      expect(ScxUpdateService.sparseIndexPath('ab'), '2/ab');
      expect(ScxUpdateService.sparseIndexPath('abc'), '3/a/abc');
    });

    test('parseSparseIndexLatest 忽略 yank 并取最高版本', () {
      const text = '''
{"name":"scx_lavd","vers":"1.1.3","yanked":false}
{"name":"scx_lavd","vers":"1.1.5","yanked":true}
{"name":"scx_lavd","vers":"1.1.4","yanked":false}
''';
      expect(ScxUpdateService.parseSparseIndexLatest(text), '1.1.4');
    });

    test('parseCratesIoLatest 读取稳定版并容错', () {
      expect(
        ScxUpdateService.parseCratesIoLatest(
          '{"crate":{"max_stable_version":"1.1.3",'
          '"newest_version":"1.1.4-beta.1"}}',
        ),
        '1.1.3',
      );
      expect(ScxUpdateService.parseCratesIoLatest('not json'), isNull);
    });

    test('parseBinVersion 提取 x.y.z 版本号', () {
      expect(ScxUpdateService.parseBinVersion('scx_loader 1.1.3\n'), '1.1.3');
      expect(ScxUpdateService.parseBinVersion('no version here'), isNull);
    });
  });
}
