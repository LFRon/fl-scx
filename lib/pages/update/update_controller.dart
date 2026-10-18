import 'package:get/get.dart';

import '../../backend/system/scx_update_service.dart';

/// 更新检查页状态：识别安装方式并比对可用版本。
class UpdateController extends GetxController {
  UpdateController({ScxUpdateService? service})
    : _service = service ?? ScxUpdateService();

  final ScxUpdateService _service;

  /// 最近一次检查结果；null 表示尚未成功检查。
  final report = Rxn<ScxUpdateReport>();

  /// 检查进行中。
  final busy = false.obs;

  /// 检查失败时的错误信息。
  final error = RxnString();

  /// 首次进入页面（或应用启动）时触发检查；已有结果时不重复请求。
  Future<void> ensureChecked() async {
    if (report.value != null || busy.value) {
      return;
    }
    await check();
  }

  /// 执行一次更新检查。
  Future<void> check() async {
    if (busy.value) {
      return;
    }
    busy.value = true;
    error.value = null;
    try {
      report.value = await _service.check();
    } catch (e) {
      error.value = '检查更新失败：$e';
    } finally {
      busy.value = false;
    }
  }
}
