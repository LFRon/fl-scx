import 'package:get/get.dart';

import '../backend/app_state.dart';
import '../pages/schedulers/schedulers_controller.dart';
import '../pages/settings/widgets/default_sched_controller.dart';

/// 应用级依赖注入：后端状态控制器与各页面控制器（常驻，跨页面保留状态）。
///
/// [ScxAppState] 通常已在 `main()` 中先注册并完成预加载，这里直接复用。
class AppBindings extends Bindings {
  @override
  void dependencies() {
    final appState = Get.isRegistered<ScxAppState>()
        ? Get.find<ScxAppState>()
        : Get.put<ScxAppState>(ScxAppState(), permanent: true);
    Get.put<SchedulersController>(
      SchedulersController(appState),
      permanent: true,
    );
    Get.put<DefaultSchedController>(
      DefaultSchedController(appState),
      permanent: true,
    );
  }
}
