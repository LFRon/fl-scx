import 'dart:io';

/// 直接读取内核 sched_ext 的状态信息（不经过 scx_loader）。
class KernelSchedExt {
  static const statePath = '/sys/kernel/sched_ext/state';
  static const opsPath = '/sys/kernel/sched_ext/root/ops';

  /// 当前内核是否暴露 sched_ext 接口。
  Future<bool> isSupported() => File(statePath).exists();

  /// 读取调度器使能状态，如 `enabled` / `disabled`。
  Future<String> state() => _readFile(statePath);

  /// 读取当前生效的调度器 ops 名称，如 `scx_lavd`，未运行为空串。
  Future<String> runningOps() => _readFile(opsPath);

  Future<String> _readFile(String path) async {
    try {
      return (await File(path).readAsString()).trim();
    } on FileSystemException {
      return '';
    }
  }
}
