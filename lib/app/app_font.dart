/// 全局打包字体族名（字体文件见 pubspec.yaml 的 `fonts` 段）。
///
/// ARM64 Desktop 下系统 CJK 字体回退异常，应用的中英文统一改用打包的
/// Noto Sans SC：主题工厂（[FlScxApp]）把该字体注入全部文字样式，通知与
/// 等宽文本等不经过主题注入的场景也引用同一常量，避免任何一处中文回退到
/// 系统字体。
const kAppFontFamily = 'Noto Sans SC';
