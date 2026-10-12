import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yaru/yaru.dart';

import '../../backend/app_state.dart';
import '../../backend/system/distro_info.dart';
import '../../backend/system/scx_installation.dart';
import '../../widgets/backend_info_box.dart';
import '../../widgets/button_styles.dart';
import '../../widgets/recommendation.dart';
import 'scx_install_controller.dart';
import 'scx_install_log_dialog.dart';

/// “未安装 scx”页面：首页在未检测到 scx / scx-loader 时显示，
/// 给出两种安装方案（软件源安装 / cargo 编译安装）。
///
/// 当 Better Deepin REPO 可用（deepin 且系统源已包含该源）时，
/// 软件源安装更快捷，会带“推荐”标识并排在第一位。
class ScxInstallView extends StatelessWidget {
  const ScxInstallView({super.key});

  @override
  Widget build(BuildContext context) {
    final app = Get.find<ScxAppState>();
    final install = Get.find<ScxInstallController>();
    final theme = Theme.of(context);

    return Obx(() {
      final busy = app.busy.value;
      final kernelSupported = app.snapshot.value.kernelState.isNotEmpty;
      final activeMethod = install.activeMethod.value;
      final progress = install.progress.value;
      final installError = install.installError.value;
      // 安装进行中或失败后，均可打开日志对话框。
      final logMethod = activeMethod ?? install.lastMethod.value;
      // Better Deepin REPO 可用时，软件源安装更快捷：推荐并排在最前。
      final repoAvailable =
          !install.probing.value &&
          install.isDeepin.value &&
          install.hasBetterDeepinRepo.value;

      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: theme.colorScheme.primary.withValues(
                  alpha: 0.12,
                ),
                child: Icon(
                  YaruIcons.download,
                  size: 32,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '尚未安装 scx',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '未检测到 scx 调度器与 scx-loader。完成安装后，即可在本应用中'
                      '启动、切换与配置 sched_ext 调度器。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!kernelSupported) ...[
            const SizedBox(height: 16),
            const BackendInfoBox(
              title: '当前内核未提供 sched_ext',
              message:
                  '未找到 /sys/kernel/sched_ext，安装调度器后可能仍无法运行；'
                  '请确认内核版本与 sched_ext 支持情况。',
              type: YaruInfoType.warning,
            ),
          ],
          const SizedBox(height: 24),
          if (repoAvailable) ...[
            _repoSection(
              context,
              busy: busy,
              activeMethod: activeMethod,
              title: '方案一：软件源安装（Better Deepin REPO）',
              recommended: true,
            ),
            const SizedBox(height: 24),
            _cargoSection(
              context,
              busy: busy,
              activeMethod: activeMethod,
              title: '方案二：cargo 编译安装',
            ),
          ] else ...[
            _cargoSection(
              context,
              busy: busy,
              activeMethod: activeMethod,
              title: '方案一：cargo 编译安装',
            ),
            const SizedBox(height: 24),
            _repoSection(
              context,
              busy: busy,
              activeMethod: activeMethod,
              title: '方案二：软件源安装（Better Deepin REPO）',
              recommended: false,
            ),
          ],
          if (activeMethod != null || installError != null) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                if (activeMethod != null) ...[
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    activeMethod != null
                        ? (progress.isEmpty ? '正在安装…' : progress)
                        : '安装未完成，可查看安装日志了解详情',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (logMethod != null)
                  TextButton(
                    style: kClickableButtonStyle,
                    onPressed: () =>
                        _showLogDialog(context, install, logMethod),
                    child: const Text('查看安装日志'),
                  ),
              ],
            ),
          ],
          if (installError != null) ...[
            const SizedBox(height: 16),
            BackendInfoBox(title: '安装失败', message: installError),
          ],
        ],
      );
    });
  }

  /// cargo 编译安装（始终可用）。
  Widget _cargoSection(
    BuildContext context, {
    required bool busy,
    required ScxInstallMethod? activeMethod,
    required String title,
  }) {
    final install = Get.find<ScxInstallController>();
    final installing = activeMethod == ScxInstallMethod.cargo;

    return YaruSection(
      headline: Text(title),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const YaruListTile(
            leading: Icon(YaruIcons.terminal),
            title: Text('从源码编译安装 scx 与 scx-loader'),
            subtitle: Text(
              '经管理员授权运行 cargo install（crates.io，走国内镜像加速），'
              '安装 scx_lavd 调度器与 scx-loader（scx_loader、scxctl），'
              '并写入 systemd / D-Bus / polkit 配置、启用服务。'
              'Rust 编译器缺失或低于 1.95 时，会先通过国内镜像（rsproxy.cn）'
              '安装 Rust 工具链；编译需要 clang、libelf-dev 等构建依赖，耗时较长。',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: FilledButton.icon(
              style: kClickableButtonStyle,
              onPressed: busy
                  ? null
                  : () => _startInstall(context, install, ScxInstallMethod.cargo),
              icon: installing ? _spinner : const Icon(YaruIcons.download),
              label: const Text('通过 cargo 安装'),
            ),
          ),
        ],
      ),
    );
  }

  /// 从 Better Deepin REPO 软件源安装（deepin 且源可用时）。
  Widget _repoSection(
    BuildContext context, {
    required bool busy,
    required ScxInstallMethod? activeMethod,
    required String title,
    required bool recommended,
  }) {
    final install = Get.find<ScxInstallController>();
    final deepin = install.isDeepin.value;
    final hasRepo = install.hasBetterDeepinRepo.value;
    final probing = install.probing.value;
    final available = !probing && deepin && hasRepo;
    final installing = activeMethod == ScxInstallMethod.apt;

    final String subtitle;
    if (probing) {
      subtitle = '正在探测发行版与软件源…';
    } else if (!deepin) {
      subtitle = '仅适用于 Deepin 系统（当前发行版不是 deepin）。';
    } else if (!hasRepo) {
      subtitle =
          '未在系统软件源中找到 Better Deepin REPO，可先添加 '
          '${DistroInfo.betterDeepinRepoUrls.join(' 或 ')}。';
    } else {
      subtitle =
          '检测到当前为 Deepin 且软件源已包含 Better Deepin REPO，'
          '可直接安装 scx-scheds（scx 调度器）与 scx-loader（守护进程、'
          'scxctl 与系统集成文件）两个软件包；安装前会先执行 apt update。';
    }

    return YaruSection(
      headline: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title),
          if (recommended) ...[
            const SizedBox(width: 8),
            const RecommendedChip(),
          ],
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          YaruListTile(
            leading: const Icon(YaruIcons.package),
            title: const Text('直接从软件源安装 scx 与 scx-loader'),
            subtitle: Text(subtitle),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: FilledButton.icon(
              style: kClickableButtonStyle,
              onPressed: (!available || busy)
                  ? null
                  : () => _confirmAptInstall(context, install),
              icon: installing ? _spinner : const Icon(YaruIcons.download),
              label: const Text('立即安装'),
            ),
          ),
        ],
      ),
    );
  }

  /// 询问用户是否现在从软件源安装，同意后执行 apt update + 安装。
  Future<void> _confirmAptInstall(
    BuildContext context,
    ScxInstallController install,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('从软件源安装 scx？'),
        content: const Text(
          '将先执行 apt update，然后安装 scx-scheds（scx 调度器）与 '
          'scx-loader（守护进程、scxctl 与系统集成文件）两个软件包。\n\n'
          '是否现在安装？',
        ),
        actions: [
          TextButton(
            style: kClickableButtonStyle,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            style: kClickableButtonStyle,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(YaruIcons.download),
            label: const Text('安装'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    _startInstall(context, install, ScxInstallMethod.apt);
  }

  /// 开始安装并弹出安装日志对话框（实时显示全部命令输出）。
  void _startInstall(
    BuildContext context,
    ScxInstallController install,
    ScxInstallMethod method,
  ) {
    unawaited(install.install(method));
    _showLogDialog(context, install, method);
  }

  /// 打开安装日志对话框；提前关闭不会中断安装，可从进度行再次打开。
  void _showLogDialog(
    BuildContext context,
    ScxInstallController install,
    ScxInstallMethod method,
  ) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) =>
            ScxInstallLogDialog(controller: install, method: method),
      ),
    );
  }

  static const _spinner = SizedBox(
    width: 16,
    height: 16,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}
