import 'package:test/test.dart';

import 'package:fl_scx/backend/config/loader_config.dart';
import 'package:fl_scx/backend/models/mode_args.dart';
import 'package:fl_scx/backend/models/sched_mode.dart';

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
  });
}
