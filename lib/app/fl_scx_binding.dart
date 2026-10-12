import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 应用自定义 Binding：在 main 中最先构造，替代
/// `WidgetsFlutterBinding.ensureInitialized()`，仅用于挂载
/// [FlScxPointerEventFilter]。
class FlScxBinding extends WidgetsFlutterBinding with FlScxPointerEventFilter {}

/// 在事件进入 [RendererBinding]（进而 [MouseTracker]）之前，过滤 Linux
/// （GTK）嵌入器在触摸屏与鼠标混用时重复发送的 Add 事件。
///
/// 嵌入器的 FlPointerManager 用单个 `pointer_inside` 标志跟踪“指针已加入”，
/// 且所有鼠标类事件共用同一个 device id（0）。触摸屏与鼠标混用时（例如平板
/// 上点几下屏幕再用鼠标），触摸设备触发的 leave 会清掉这个共享标志并发送一次
/// kind=touch 的 Remove——MouseTracker 不处理 touch 事件，设备仍是 Added；
/// 随后鼠标移动经 ensure_pointer_added 又补发一次 kind=mouse 的 Add，于是同一
/// 设备在未 Remove 的情况下收到两次 Add，触发 MouseTracker 的不变量断言：
///
///   mouse_tracker.dart: Failed assertion:
///   (event is PointerAddedEvent) == (lastEvent is PointerRemovedEvent)
///
/// 这里丢弃这种重复的 Add（指针实际并未离开窗口，丢弃后与框架已有状态一致），
/// 其余事件原样放行。根因在嵌入器的 FlPointerManager（应按设备类型分别跟踪
/// `pointer_inside`），上游修复后本混入即可删除。
mixin FlScxPointerEventFilter on GestureBinding {
  // 镜像 MouseTracker 处理范围（mouse/stylus）内，各设备当前是否处于
  // Added 状态（与其内部 _mouseStates 同一事件流、同一规则）。
  final Set<int> _presentPointerDevices = <int>{};

  @override
  void dispatchEvent(PointerEvent event, HitTestResult? hitTestResult) {
    if (event.kind == PointerDeviceKind.mouse ||
        event.kind == PointerDeviceKind.stylus) {
      if (event is PointerSignalEvent) {
        // 滚轮等信号事件不改变设备的增删状态，直接放行。
      } else if (event is PointerAddedEvent) {
        if (!_presentPointerDevices.add(event.device)) {
          // 重复的 Add：设备已在 Added 状态，丢弃。
          return;
        }
      } else if (event is PointerRemovedEvent) {
        _presentPointerDevices.remove(event.device);
      } else {
        _presentPointerDevices.add(event.device);
      }
    }
    super.dispatchEvent(event, hitTestResult);
  }
}
