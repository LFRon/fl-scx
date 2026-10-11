import 'package:get/get.dart';
import 'package:yaru/yaru.dart';

/// 侧边栏导航状态：页面索引与“关于”底部固定条目。
class HomeController extends GetxController {
  /// “关于”页面索引：列在主列表之后，由侧边栏底部条目呈现。
  static const aboutIndex = 3;

  /// Yaru 主从布局的页面控制器。
  late final pages = YaruPageController(
    length: aboutIndex + 1,
    initialIndex: 0,
  );

  /// 当前选中的侧边栏索引（用于底部条目高亮）。
  final selectedIndex = 0.obs;

  /// 主列表点选后同步高亮状态（页面切换已由 Yaru 控制器完成）。
  void syncSelection(int? index) {
    if (index != null) {
      selectedIndex.value = index;
    }
  }

  /// 选中指定页面（含底部“关于”条目触发的切换）。
  void select(int index) {
    selectedIndex.value = index;
    pages.index = index;
  }

  @override
  void onClose() {
    pages.dispose();
    super.onClose();
  }
}
