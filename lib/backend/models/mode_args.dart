import 'sched_mode.dart';

/// 某个调度器在指定模式下的解析结果参数（由 scx_loader 计算）。
class ModeArgs {
  const ModeArgs(this.mode, this.args);

  final SchedMode mode;

  /// 该模式实际会传给调度器的参数列表。
  final List<String> args;

  bool get hasArgs => args.isNotEmpty;

  /// 用于界面展示的参数文本。
  String get argsText => args.isEmpty ? '' : args.join(' ');
}

/// 从完整调度器名（如 `scx_lavd`）取得简短名称（`lavd`）。
String shortSchedulerName(String scheduler) =>
    scheduler.startsWith('scx_') ? scheduler.substring(4) : scheduler;

/// 从简短名称补全为完整调度器名。
String fullSchedulerName(String scheduler) =>
    scheduler.startsWith('scx_') ? scheduler : 'scx_$scheduler';
