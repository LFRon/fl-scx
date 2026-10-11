import 'package:flutter/foundation.dart';

import 'mode_args.dart';
import 'sched_mode.dart';

/// scx_loader systemd 服务状态。
class SystemServiceState {
  const SystemServiceState({this.active = false, this.enabled = false});

  /// 服务当前是否运行。
  final bool active;

  /// 服务是否设置了开机自启。
  final bool enabled;

  static const unknown = SystemServiceState();

  @override
  bool operator ==(Object other) =>
      other is SystemServiceState &&
      other.active == active &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(active, enabled);
}

/// 一次刷新得到的完整系统快照，界面只依赖该快照渲染。
class ScxSnapshot {
  const ScxSnapshot({
    required this.daemonAvailable,
    required this.currentScheduler,
    required this.currentMode,
    required this.currentArgs,
    required this.supportedSchedulers,
    required this.defaultScheduler,
    required this.defaultMode,
    required this.kernelState,
    required this.kernelOps,
    required this.service,
    required this.configPath,
    this.errorMessage,
  });

  /// scx_loader 的 D-Bus 接口是否可用。
  final bool daemonAvailable;

  /// 当前正在运行的调度器完整名，未运行为 `unknown`。
  final String currentScheduler;

  /// 当前调度器模式。
  final SchedMode currentMode;

  /// 当前调度器运行时参数。
  final List<String> currentArgs;

  /// scx_loader 支持的调度器列表（完整名）。
  final List<String> supportedSchedulers;

  /// 配置文件中配置的默认调度器。
  final String defaultScheduler;

  /// 配置文件中配置的默认模式。
  final SchedMode defaultMode;

  /// `/sys/kernel/sched_ext/state` 的内容，如 `enabled`。
  final String kernelState;

  /// `/sys/kernel/sched_ext/root/ops` 的内容，如 `scx_lavd`。
  final String kernelOps;

  /// scx_loader systemd 服务状态。
  final SystemServiceState service;

  /// 实际使用的 scx_loader 配置文件路径。
  final String configPath;

  /// 后端收集信息时出现的错误（一般为 D-Bus 连接问题）。
  final String? errorMessage;

  /// 当前是否有调度器在运行。
  bool get schedulerRunning =>
      daemonAvailable &&
      currentScheduler.isNotEmpty &&
      currentScheduler != 'unknown';

  /// 是否配置了开机默认调度器。
  bool get hasDefaultScheduler =>
      defaultScheduler.isNotEmpty && defaultScheduler != 'unknown';

  /// 内核 sched_ext 是否已启用。
  bool get kernelEnabled => kernelState.trim() == 'enabled';

  static const empty = ScxSnapshot(
    daemonAvailable: false,
    currentScheduler: 'unknown',
    currentMode: SchedMode.auto,
    currentArgs: <String>[],
    supportedSchedulers: <String>[],
    defaultScheduler: 'unknown',
    defaultMode: SchedMode.auto,
    kernelState: '',
    kernelOps: '',
    service: SystemServiceState.unknown,
    configPath: '',
  );

  @override
  bool operator ==(Object other) =>
      other is ScxSnapshot &&
      other.daemonAvailable == daemonAvailable &&
      other.currentScheduler == currentScheduler &&
      other.currentMode == currentMode &&
      listEquals(other.currentArgs, currentArgs) &&
      listEquals(other.supportedSchedulers, supportedSchedulers) &&
      other.defaultScheduler == defaultScheduler &&
      other.defaultMode == defaultMode &&
      other.kernelState == kernelState &&
      other.kernelOps == kernelOps &&
      other.service == service &&
      other.configPath == configPath &&
      other.errorMessage == errorMessage;

  @override
  int get hashCode => Object.hash(
    daemonAvailable,
    currentScheduler,
    currentMode,
    Object.hashAll(currentArgs),
    Object.hashAll(supportedSchedulers),
    defaultScheduler,
    defaultMode,
    kernelState,
    kernelOps,
    service,
    configPath,
    errorMessage,
  );
}

/// 单个调度器在界面侧的完整描述（支持列表 + 模式参数缓存）。
class SchedulerInfo {
  const SchedulerInfo({
    required this.name,
    this.modeArgs = const <ModeArgs>[],
    this.configuredModes = const <SchedMode>{},
    this.loading = false,
    this.error,
  });

  /// 完整调度器名，如 `scx_lavd`。
  final String name;

  /// scx_loader 解析出的各模式参数。
  final List<ModeArgs> modeArgs;

  /// 有实际配置参数的模式集合。
  final Set<SchedMode> configuredModes;

  /// 是否正在从后端加载模式信息。
  final bool loading;

  /// 加载模式信息时的错误信息。
  final String? error;

  ModeArgs? argsFor(SchedMode mode) {
    for (final entry in modeArgs) {
      if (entry.mode == mode) {
        return entry;
      }
    }
    return null;
  }

  SchedulerInfo copyWith({
    List<ModeArgs>? modeArgs,
    Set<SchedMode>? configuredModes,
    bool? loading,
    String? error,
    bool clearError = false,
  }) => SchedulerInfo(
    name: name,
    modeArgs: modeArgs ?? this.modeArgs,
    configuredModes: configuredModes ?? this.configuredModes,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
  );
}

/// 后端操作的统一结果。
class BackendResult {
  const BackendResult.success() : error = null;
  const BackendResult.failure(String message) : error = message;

  /// 为空表示成功，否则为可直接展示的错误信息。
  final String? error;

  bool get isSuccess => error == null;

  static BackendResult fromError(Object? error) => error == null
      ? const BackendResult.success()
      : BackendResult.failure(error.toString());
}
