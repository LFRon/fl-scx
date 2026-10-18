import 'dart:async';

import 'package:get/get.dart';

import '../backend/app_state.dart';
import '../pages/home/home_controller.dart';
import '../pages/install/scx_install_controller.dart';
import '../pages/schedulers/schedulers_controller.dart';
import '../pages/settings/widgets/default_sched_controller.dart';
import '../pages/update/update_controller.dart';

/// 应用级依赖注入：后端状态控制器与各页面控制器（常驻，跨页面保留状态）。
///
/// [ScxAppState] 通常已在 `main()` 中先注册并完成预加载，这里直接复用。
class AppBindings extends Bindings {
  @override
  void dependencies() {
    final appState = Get.isRegistered<ScxAppState>()
        ? Get.find<ScxAppState>()
        : Get.put<ScxAppState>(ScxAppState(), permanent: true);
    Get.put<HomeController>(HomeController(), permanent: true);
    Get.put<ScxInstallController>(
      ScxInstallController(appState),
      permanent: true,
    );
    Get.put<SchedulersController>(
      SchedulersController(appState),
      permanent: true,
    );
    Get.put<DefaultSchedController>(
      DefaultSchedController(appState),
      permanent: true,
    );
    Get.put<UpdateController>(UpdateController(), permanent: true);
    // 启动后在后台检查一次更新，让侧边栏“更新”红点及时反映可用更新；
    // 结果在会话内保留，进入更新页不会重复请求。
    unawaited(Get.find<UpdateController>().ensureChecked());
  }
}
