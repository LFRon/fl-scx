import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yaru/yaru.dart';

import '../../backend/system/scx_installation.dart';
import '../../backend/system/scx_update_service.dart';
import '../../pages/install/scx_install_controller.dart';
import '../../pages/install/scx_install_log_dialog.dart';
import '../../widgets/button_styles.dart';
import '../../widgets/status_chip.dart';
import 'update_controller.dart';

/// 更新检查页：展示 scx 的安装方式，并比对软件源 / crates.io 的可用版本。
///
/// 首次进入时自动检查一次（结果在会话内保留），也可手动重新检查；
/// 发现更新时提供对应操作：
/// - cargo 安装：通过国内镜像直接覆盖更新（用户级免授权；系统级经授权）；
/// - 软件源安装：仅弹窗提示通过系统内置更新方式升级，不做其它操作。
class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key});

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  final controller = Get.find<UpdateController>();
  final install = Get.find<ScxInstallController>();

  @override
  void initState() {
    super.initState();
    controller.ensureChecked();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return YaruDetailPage(
      // 详情区标题栏承担窗口标题栏角色（窗口控制按钮在窗口右上角）。
      appBar: YaruWindowTitleBar(
        leading: Navigator.of(context).canPop() ? const YaruBackButton() : null,
        title: const Text('更新检查'),
      ),
      body: Obx(() {
        final report = controller.report.value;
        final busy = controller.busy.value;
        final error = controller.error.value;
        final updating = install.activeMethod.value != null;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                FilledButton.icon(
                  style: kClickableButtonStyle,
                  onPressed: busy || updating ? null : controller.check,
                  icon: busy ? _spinner : const Icon(YaruIcons.refresh),
                  label: const Text('检查更新'),
                ),
                if (report != null && report.hasUpdate) ...[
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: kClickableButtonStyle,
                    onPressed: updating
                        ? null
                        : () => _onUpdate(context, report),
                    icon: updating
                        ? _spinner
                        : Icon(
                            report.setup == ScxSetupKind.cargo
                                ? YaruIcons.download
                                : YaruIcons.question,
                          ),
                    label: Text(
                      report.setup == ScxSetupKind.cargo ? '立即更新' : '如何更新',
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            if (error != null)
              YaruSection(
                headline: const Text('更新检查'),
                child: YaruListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const Text('检查失败'),
                  subtitle: Text(error),
                ),
              )
            else if (report == null)
              // 检查进行中：只显示加载指示，不展示多余文字。
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else ...[
              YaruSection(
                headline: const Text('安装方式'),
                child: YaruListTile(
                  leading: Icon(_methodIcon(report.setup)),
                  title: const Text('安装方式'),
                  subtitle: Text(_methodHint(report.setup)),
                  trailing: StatusChip(
                    label: _methodLabel(report.setup),
                    color: report.setup == ScxSetupKind.unknown
                        ? theme.colorScheme.outline
                        : theme.colorScheme.primary,
                  ),
                ),
              ),
              if (report.setup != ScxSetupKind.unknown) ...[
                const SizedBox(height: 16),
                YaruSection(
                  headline: const Text('版本检查'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final component in report.components)
                        YaruListTile(
                          leading: Icon(_componentIcon(component.name)),
                          title: Text(_componentLabel(component.name)),
                          subtitle: Text(_versionText(report, component)),
                          trailing: _stateChip(context, component.state),
                        ),
                      if (report.note != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                          child: Text(
                            report.note!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        );
      }),
    );
  }

  /// 更新操作：cargo 直接覆盖更新；软件源仅弹窗告知系统更新方式。
  Future<void> _onUpdate(BuildContext context, ScxUpdateReport report) async {
    if (report.setup != ScxSetupKind.cargo) {
      await showDialog<void>(
        context: context,
        builder: (_) => _SystemUpdateDialog(report: report),
      );
      return;
    }
    // 覆盖更新与日志对话框并行：提前关闭对话框不会中断更新。
    unawaited(_runCargoUpdate(report));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => ScxInstallLogDialog(
          controller: install,
          method: ScxInstallMethod.cargo,
          update: true,
        ),
      ),
    );
  }

  /// cargo 覆盖更新：用户级安装免授权直达，系统级安装经管理员会话；
  /// 完成后重新检查以刷新状态与红点。
  Future<void> _runCargoUpdate(ScxUpdateReport report) async {
    final crates = <String>[
      for (final component in report.components)
        if (component.state == ScxVersionState.updateAvailable &&
            ScxUpdateService.cargoCrates.contains(component.name))
          component.name,
    ];
    if (report.cargoUserLevel) {
      await install.updateUserLevelCargo(crates);
    } else {
      await install.install(ScxInstallMethod.cargo);
    }
    await controller.check();
  }

  /// 安装方式图标。
  IconData _methodIcon(ScxSetupKind kind) => switch (kind) {
    ScxSetupKind.systemRepo => YaruIcons.download,
    ScxSetupKind.cargo => YaruIcons.terminal,
    ScxSetupKind.unknown => YaruIcons.question,
  };

  /// 安装方式标签。
  String _methodLabel(ScxSetupKind kind) => switch (kind) {
    ScxSetupKind.systemRepo => '系统源安装',
    ScxSetupKind.cargo => '通过 cargo 安装',
    ScxSetupKind.unknown => '未知',
  };

  /// 安装方式说明。
  String _methodHint(ScxSetupKind kind) => switch (kind) {
    ScxSetupKind.systemRepo => '由系统软件包安装（scx-scheds、scx-loader），升级同样通过软件源进行。',
    ScxSetupKind.cargo => '由 cargo 编译安装（crates.io），可通过本页直接覆盖更新。',
    ScxSetupKind.unknown => '未能识别 scx 的安装方式，无法自动检查更新。',
  };

  /// 组件名称（软件包 / crate）对应的中文说明。
  String _componentLabel(String name) => switch (name) {
    'scx-scheds' => '调度器套件（scx-scheds）',
    'scx-loader' => '加载器（scx-loader）',
    'scx_loader' => '加载器（scx_loader）',
    'scx_lavd' => '调度器（scx_lavd）',
    'scxctl' => '命令行工具（scxctl）',
    _ => name,
  };

  /// 组件图标。
  IconData _componentIcon(String name) => switch (name) {
    'scx-scheds' || 'scx_lavd' => YaruIcons.ordered_list_new,
    'scx-loader' || 'scx_loader' => YaruIcons.gear,
    'scxctl' => YaruIcons.terminal,
    _ => YaruIcons.download,
  };

  /// 版本明细行：已安装版本与可用最新版本。
  String _versionText(ScxUpdateReport report, ScxComponentCheck component) {
    final latestLabel = report.setup == ScxSetupKind.systemRepo
        ? '软件源最新'
        : 'crates.io 最新';
    final installed = component.installedVersion ?? '未知';
    final latest = component.latestVersion ?? '未知';
    return '已安装 $installed · $latestLabel $latest';
  }

  /// 版本状态标签。
  Widget _stateChip(BuildContext context, ScxVersionState state) {
    final colors = YaruColors.of(context);
    return switch (state) {
      ScxVersionState.upToDate => StatusChip(
        label: '已是最新',
        color: StatusChip.successColor(context),
      ),
      ScxVersionState.updateAvailable => StatusChip(
        label: '可更新',
        color: colors.warning,
      ),
      ScxVersionState.unknown => StatusChip(
        label: '未知',
        color: Theme.of(context).colorScheme.outline,
      ),
    };
  }
}

/// 软件源安装的更新提示对话框：仅告知通过系统内置更新方式升级。
class _SystemUpdateDialog extends StatelessWidget {
  const _SystemUpdateDialog({required this.report});

  final ScxUpdateReport report;

  @override
  Widget build(BuildContext context) {
    final outdated = <String>[
      for (final component in report.components)
        if (component.state == ScxVersionState.updateAvailable)
          '${component.name}（${component.installedVersion} → '
              '${component.latestVersion}）',
    ];
    return AlertDialog(
      title: const Text('发现新版本'),
      content: Text(
        '软件源中的 ${outdated.join('、')} 有可用更新。\n\n'
        '为避免与系统包管理冲突，本应用不会直接修改系统软件包，'
        '请通过系统内置的更新方式（“系统更新”、软件管理器或'
        '软件源升级）完成升级。',
      ),
      actions: [
        TextButton(
          style: kClickableButtonStyle,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}

const _spinner = SizedBox(
  width: 16,
  height: 16,
  child: CircularProgressIndicator(strokeWidth: 2),
);
