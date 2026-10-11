/// 调度器控制操作类型，用于界面展示“进行中”状态。
enum SchedulerOperation {
  start('启动中'),
  switchTo('切换中'),
  stop('停止中'),
  restart('重启中'),
  restore('恢复中');

  const SchedulerOperation(this.label);

  /// 进行中的按钮提示文字。
  final String label;
}
