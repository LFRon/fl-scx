import 'dart:async';

import 'package:get/get.dart';

import '../../backend/app_state.dart';
import '../../backend/system/distro_info.dart';
import '../../backend/system/scx_installation.dart';

/// “未安装 scx”页的界面状态：发行版/软件源探测与安装进度。
///
/// 是否显示本页由统一的 [ScxAppState.scxInstalled] 开关决定；
/// 安装完成后该开关随快照刷新而翻转，本页自动让位给正常界面。
class ScxInstallController extends GetxController {
  ScxInstallController(this.app);

  final ScxAppState app;

  /// 环境探测是否仍在进行。
  final probing = true.obs;

  /// 当前发行版是否为 deepin。
  final isDeepin = false.obs;

  /// 系统软件源中是否包含 Better Deepin REPO。
  final hasBetterDeepinRepo = false.obs;

  /// 正在进行的安装方式（null 表示空闲）。
  final activeMethod = Rxn<ScxInstallMethod>();

  /// 最近一次安装使用的方式（用于失败后重新打开日志对话框）。
  final lastMethod = Rxn<ScxInstallMethod>();

  /// 当前安装阶段文本（来自安装流程的进度回调）。
  final progress = ''.obs;

  /// 本次安装的全部命令输出（安装日志对话框逐行实时显示）。
  final logLines = <String>[].obs;

  /// 最近一次安装失败的详细信息。
  final installError = Rxn<String>();

  @override
  void onInit() {
    super.onInit();
    unawaited(_probe());
  }

  /// 探测发行版与软件源（只读，不触发授权）。
  Future<void> _probe() async {
    final deepin = await DistroInfo.isDeepin();
    final repo = deepin && await DistroInfo.hasBetterDeepinRepo();
    isDeepin.value = deepin;
    hasBetterDeepinRepo.value = repo;
    probing.value = false;
  }

  /// 以 [method] 方式安装 scx 与 scx-loader；返回 null 表示成功。
  ///
  /// 安装期间的全部命令输出实时追加到 [logLines]（日志对话框展示）。
  Future<String?> install(ScxInstallMethod method) async {
    installError.value = null;
    logLines.clear();
    activeMethod.value = method;
    lastMethod.value = method;
    progress.value = method == ScxInstallMethod.apt ? '准备从软件源安装…' : '准备编译安装…';
    try {
      final error = await app.installScx(
        method,
        onProgress: (text) => progress.value = text,
        onLog: (line) => logLines.add(line),
      );
      installError.value = error;
      return error;
    } finally {
      activeMethod.value = null;
    }
  }

  /// 用户级 cargo 覆盖更新（无需管理员授权，走国内镜像）。
  ///
  /// 复用与安装相同的进度与日志状态（[progress]、[logLines]），
  /// 安装日志对话框可直接展示；返回 null 表示成功。
  Future<String?> updateUserLevelCargo(List<String> crates) async {
    installError.value = null;
    logLines.clear();
    activeMethod.value = ScxInstallMethod.cargo;
    lastMethod.value = ScxInstallMethod.cargo;
    progress.value = '准备覆盖更新…';
    try {
      final error = await app.updateUserLevelCargo(
        crates,
        onProgress: (text) => progress.value = text,
        onLog: (line) => logLines.add(line),
      );
      installError.value = error;
      return error;
    } finally {
      activeMethod.value = null;
    }
  }
}
