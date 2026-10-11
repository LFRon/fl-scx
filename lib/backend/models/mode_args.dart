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

/// 将内核 ops 名称简约化为调度器短名。
///
/// 内核 `/sys/kernel/sched_ext/root/ops` 的内容由调度器自身设置，
/// 常见形如 `lavd_1.1.3_x86_64_unknown_linux_gnu`（短名+版本+目标三元组），
/// 也可能直接是 `scx_lavd`、`lavd-1.1.3` 等其它变体。
String shortKernelOpsName(String ops) {
  final trimmed = ops.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final withoutPrefix = trimmed.startsWith('scx_')
      ? trimmed.substring(4)
      : trimmed;
  return withoutPrefix.split(RegExp(r'[^a-zA-Z0-9]')).first;
}

/// 判断内核 ops 是否对应指定调度器（完整名）。
///
/// 使用模糊匹配以兼容各调度器自定义的 ops 名称格式：
/// 名称以短名开头且其后是数字或非字母字符（如 `lavd_1.1.3`、
/// `lavd1.1.3`、`lavd-1.1.3`），或按非字母数字分隔后包含短名
/// 独立词（如 `scx-lavd-1.1.3`），都视为匹配；
/// `lavdx` 这类“短名后紧跟字母”的名称不会误判。
bool kernelOpsMatches(String kernelOps, String scheduler) {
  final short = shortSchedulerName(scheduler).toLowerCase();
  final ops = kernelOps.trim().toLowerCase();
  if (short.isEmpty || ops.isEmpty) {
    return false;
  }
  if (_startsAsToken(ops, short)) {
    return true;
  }
  return ops.split(RegExp(r'[^a-z0-9]+')).contains(short);
}

/// [name] 是否以 [token] 开头，且其后为结尾、数字或非字母字符。
bool _startsAsToken(String name, String token) {
  if (!name.startsWith(token)) {
    return false;
  }
  if (name.length == token.length) {
    return true;
  }
  final next = name.codeUnitAt(token.length);
  final isDigit = next >= 0x30 && next <= 0x39;
  final isLetter =
      (next >= 0x61 && next <= 0x7a) || (next >= 0x41 && next <= 0x5a);
  return isDigit || !isLetter;
}
