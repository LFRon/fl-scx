import 'package:test/test.dart';

import 'package:fl_scx/backend/config/loader_config.dart';
import 'package:fl_scx/backend/models/mode_args.dart';
import 'package:fl_scx/backend/models/sched_mode.dart';
import 'package:fl_scx/backend/models/scx_snapshot.dart';
import 'package:fl_scx/backend/system/scx_control_service.dart';

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
  });
}
