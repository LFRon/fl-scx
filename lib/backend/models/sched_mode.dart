/// sched_ext 调度模式，数值与 scx_loader D-Bus 接口保持一致。
enum SchedMode {
  auto(0, 'Auto', '自动', '使用调度器内置的默认配置'),
  gaming(1, 'Gaming', '游戏', '面向游戏与交互场景，优化响应延迟'),
  powerSave(2, 'PowerSave', '省电', '降低功耗，适合移动办公与续航场景'),
  lowLatency(3, 'LowLatency', '低延迟', '最小化调度延迟，适合实时负载'),
  server(4, 'Server', '服务器', '偏向吞吐量，适合服务器与编译任务');

  const SchedMode(this.raw, this.tomlName, this.label, this.description);

  /// D-Bus / sysfs 使用的数值。
  final int raw;

  /// scx_loader 配置文件中使用的名称。
  final String tomlName;

  /// 界面显示名称。
  final String label;

  /// 界面提示说明。
  final String description;

  /// 由 scx_loader 返回的数值还原为 [SchedMode]，未知值回退到 [auto]。
  static SchedMode fromRaw(int raw) => SchedMode.values.firstWhere(
    (mode) => mode.raw == raw,
    orElse: () => SchedMode.auto,
  );

  /// 解析配置文件中的模式名称（不区分大小写）。
  static SchedMode fromTomlName(String name) {
    final lower = name.trim().toLowerCase();
    return SchedMode.values.firstWhere(
      (mode) => mode.tomlName.toLowerCase() == lower,
      orElse: () => SchedMode.auto,
    );
  }
}
