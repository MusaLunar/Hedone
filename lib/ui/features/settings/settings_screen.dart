import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_dependencies.dart';
import '../../../core/theme/hedone_theme.dart';
import '../../../core/theme/md3_tokens.dart';
import '../../../core/utils/jm_image_descrambler.dart';
import '../../../data/jmcomic/jm_api_service.dart';
import '../../../domain/models/reader_models.dart';
import '../../prism/prism_navigation_dock.dart';
import '../../prism/prism_segmented_control.dart';
import '../../prism/prism_theme_preview.dart';
import '../../widgets/jm_descrambled_image.dart';
import '../../widgets/md3_segmented_list.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.deps,
  });

  final AppDependencies deps;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    widget.deps.store.addListener(_onChanged);
    widget.deps.tagTranslator.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.deps.store.removeListener(_onChanged);
    widget.deps.tagTranslator.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _showJmHostSpeedDialog() async {
    await widget.deps.jmApi.refreshHostList(silent: true);
    final hosts = widget.deps.jmApi.availableHosts;
    final results = <String, JmHostSpeedResult?>{
      for (final h in hosts) h: null,
    };
    var testing = true;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            if (testing) {
              testing = false;
              for (final h in hosts) {
                widget.deps.jmApi.pingHost(h).then((res) {
                  if (ctx.mounted) {
                    setDialogState(() => results[h] = res);
                  }
                });
              }
            }

            final customCtrl = TextEditingController();
            return AlertDialog(
              title: const Text('JMComic 线路测速与切换'),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...hosts.map((host) {
                        final res = results[host];
                        final selected = widget.deps.store.jmApiHost == host;
                        final ms = res?.latencyMs;
                        final csDialog = Theme.of(ctx).colorScheme;
                        final color = ms == null
                            ? (res == null
                                ? csDialog.onSurfaceVariant
                                : csDialog.error)
                            : (ms <= 450
                                ? Colors.green
                                : (ms <= 1100 ? Colors.orange : csDialog.error));
                        return ListTile(
                          selected: selected,
                          leading: Icon(Icons.circle, size: 12, color: color),
                          title: Text(host),
                          subtitle: Text(
                            widget.deps.jmApi.hostLabels[host] ?? 'API 节点',
                          ),
                          trailing: Text(
                            res == null
                                ? '测速中...'
                                : (ms != null ? '${ms}ms' : '超时'),
                            style: Md3Typography.tabularFigures(
                              Md3Typography.emphasized(
                                Theme.of(ctx)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(color: color),
                              ),
                            ),
                          ),
                          onTap: () async {
                            await widget.deps.store.setJmNetwork(
                              apiHost: host,
                              imgHost: res?.imgHost,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                        );
                      }),
                      const Divider(),
                      TextField(
                        controller: customCtrl,
                        decoration: const InputDecoration(
                          labelText: '自定义域名（不含 https://）',
                          hintText: '例如 www.cdnbtd.cc',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('关闭'),
                ),
                FilledButton(
                  onPressed: () async {
                    final manual = customCtrl.text.trim();
                    if (manual.isNotEmpty) {
                      await widget.deps.store.setJmNetwork(apiHost: manual);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('使用自定义'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showJmLoginDialog() async {
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    var busy = false;
    String? errMsg;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('登录 JMComic'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: userCtrl,
                    decoration: const InputDecoration(labelText: '用户名 / 邮箱'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '密码'),
                  ),
                  if (errMsg != null) ...[
                    const SizedBox(height: Md3Spacing.s8),
                    Text(
                      errMsg!,
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.error,
                          ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setDialogState(() {
                            busy = true;
                            errMsg = null;
                          });
                          try {
                            await widget.deps.jmRepo
                                .login(userCtrl.text, passCtrl.text);
                            if (ctx.mounted) Navigator.pop(ctx);
                          } catch (e) {
                            setDialogState(() {
                              busy = false;
                              errMsg = e.toString();
                            });
                          }
                        },
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('登录'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEhCookieDialog() async {
    final memberCtrl = TextEditingController(text: widget.deps.store.ehMemberId);
    final hashCtrl = TextEditingController(text: widget.deps.store.ehPassHash);
    final igneousCtrl = TextEditingController(text: widget.deps.store.ehIgneous);

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('E-Hentai Cookie 登录'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: memberCtrl,
                  decoration: const InputDecoration(labelText: 'ipb_member_id'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: hashCtrl,
                  decoration: const InputDecoration(labelText: 'ipb_pass_hash'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: igneousCtrl,
                  decoration: const InputDecoration(
                    labelText: 'igneous（访问 ExHentai 需要）',
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      final raw = data?.text ?? '';
                      final mId = RegExp(r'ipb_member_id[=:\s]+([0-9]+)')
                          .firstMatch(raw)
                          ?.group(1);
                      final pHash = RegExp(r'ipb_pass_hash[=:\s]+([0-9a-fA-F]{32})')
                          .firstMatch(raw)
                          ?.group(1);
                      final ign = RegExp(r'igneous[=:\s]+([0-9a-zA-Z]+)')
                          .firstMatch(raw)
                          ?.group(1);
                      if (mId != null) memberCtrl.text = mId;
                      if (pHash != null) hashCtrl.text = pHash;
                      if (ign != null) igneousCtrl.text = ign;
                    },
                    icon: const Icon(Icons.content_paste_go_rounded, size: 18),
                    label: const Text('从剪贴板自动提取'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                await widget.deps.store.setEhCookies(
                  memberId: memberCtrl.text,
                  passHash: hashCtrl.text,
                  igneous: igneousCtrl.text,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('保存 Cookie'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showEhPasswordLoginDialog() async {
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    var busy = false;
    String? errMsg;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('E-Hentai 论坛账号登录'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: userCtrl,
                      decoration: const InputDecoration(labelText: '用户名'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: '密码'),
                    ),
                    const SizedBox(height: Md3Spacing.s8),
                    Text(
                      '提示：若当前 IP 触发 E-Hentai 论坛人机验证（CAPTCHA），请改用「配置 Cookie」方式登录。',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    if (errMsg != null) ...[
                      const SizedBox(height: Md3Spacing.s8),
                      Text(
                        errMsg!,
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                              color: Theme.of(ctx).colorScheme.error,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _showEhCookieDialog();
                        },
                  child: const Text('改用 Cookie'),
                ),
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setDialogState(() {
                            busy = true;
                            errMsg = null;
                          });
                          try {
                            final res = await widget.deps.ehApi
                                .signInWithPassword(userCtrl.text, passCtrl.text);
                            if (res.success) {
                              if (ctx.mounted) Navigator.pop(ctx);
                            } else {
                              setDialogState(() {
                                busy = false;
                                errMsg = res.errorMessage;
                              });
                            }
                          } catch (e) {
                            setDialogState(() {
                              busy = false;
                              errMsg = e.toString();
                            });
                          }
                        },
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('登录'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showProxyDialog() async {
    final ctrl = TextEditingController(text: widget.deps.store.proxyAddress);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('HTTP 代理设置'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: '代理地址（留空则直连）',
            hintText: '例如 127.0.0.1:7890',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await widget.deps.store.setNetworkConfig(proxyAddress: ctrl.text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.deps.store;
    final translator = widget.deps.tagTranslator;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pageMargin = Md3Breakpoints.pageMargin(MediaQuery.sizeOf(context).width);
    const switchTilePadding = EdgeInsets.only(
      left: Md3Spacing.s16,
      right: Md3Spacing.s24,
      top: Md3Spacing.s4,
      bottom: Md3Spacing.s4,
    );
    final normalizedContrast = store.contrastLevel >= 0.75
        ? 1.0
        : (store.contrastLevel >= 0.25 ? 0.5 : 0.0);
    final bottomInset = PrismBottomInsetScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '设置与账号',
          style: Md3Typography.emphasized(theme.textTheme.titleLarge),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          pageMargin,
          Md3Spacing.s8,
          pageMargin,
          Md3Spacing.s32 + bottomInset,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Brand Header Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Md3Spacing.s16),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(Md3Shapes.medium),
                            child: Image.asset(
                              'assets/images/logo.png',
                              width: 56,
                              height: 56,
                            ),
                          ),
                          const SizedBox(width: Md3Spacing.s16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Hedone',
                                  style: Md3Typography.emphasized(
                                    theme.textTheme.titleLarge,
                                  ),
                                ),
                                const SizedBox(height: Md3Spacing.s2),
                                Text(
                                  'JMComic × E-Hentai 双源 Material Design 3 漫画阅读器',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Md3SectionHeader('JMComic 专线与账号'),
                  Md3SegmentedListGroup(
                    children: [
                      Md3ListTile(
                        leading: const Icon(Icons.speed_rounded),
                        title: const Text('API 线路切换与测速'),
                        subtitle: Text('当前线路：${store.jmApiHost}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _showJmHostSpeedDialog,
                      ),
                      Md3ListTile(
                        leading: const Icon(Icons.image_outlined),
                        title: const Text('图片 CDN 分流'),
                        subtitle: Text(
                          '图源 ${store.jmImgShunt} · ${store.jmImgHost}',
                          style: Md3Typography.tabularFigures(null),
                        ),
                        trailing: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: store.jmImgShunt,
                            items: const [1, 2, 3, 4]
                                .map(
                                  (i) => DropdownMenuItem(
                                    value: i,
                                    child: Text('图源$i'),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) async {
                              if (v != null) {
                                await store.setJmNetwork(imgShunt: v);
                                await widget.deps.jmApi
                                    .syncSetting(silent: true);
                              }
                            },
                          ),
                        ),
                      ),
                      Md3ListTile(
                        leading: const Icon(Icons.person_outline_rounded),
                        title: Text(
                          store.isJmLoggedIn
                              ? '已登录：${store.jmUsername}'
                              : '登录 JMComic 账号',
                        ),
                        subtitle: const Text('支持同步云端收藏与发表评论'),
                        trailing: store.isJmLoggedIn
                            ? TextButton(
                                onPressed: store.clearJmAuth,
                                child: const Text('退出'),
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: store.isJmLoggedIn ? null : _showJmLoginDialog,
                      ),
                    ],
                  ),

                  const Md3SectionHeader('E-Hentai / ExHentai 与标签汉化'),
                  Md3SegmentedListGroup(
                    children: [
                      SwitchListTile(
                        contentPadding: switchTilePadding,
                        secondary: const Icon(Icons.visibility_outlined),
                        title: const Text('启用 ExHentai 里站'),
                        subtitle: Text(
                          store.isEhLoggedIn
                              ? '已配置账号 Cookie'
                              : '需要先配置 Cookie（包含 igneous）',
                        ),
                        value: store.ehUseExHentai,
                        onChanged: (v) {
                          if (v && !store.isEhLoggedIn) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('请先配置 E-Hentai Cookie'),
                              ),
                            );
                            return;
                          }
                          store.setEhUseExHentai(v);
                        },
                      ),
                      Md3ListTile(
                        leading: const Icon(Icons.cookie_outlined),
                        title: Text(
                          store.isEhLoggedIn
                              ? 'Cookie 已配置 (UID: ${store.ehMemberId})'
                              : 'Cookie 登录',
                          style: Md3Typography.tabularFigures(null),
                        ),
                        subtitle: const Text(
                          '输入 ipb_member_id / ipb_pass_hash / igneous',
                        ),
                        trailing: store.isEhLoggedIn
                            ? TextButton(
                                onPressed: store.clearEhCookies,
                                child: const Text('清除'),
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: _showEhCookieDialog,
                      ),
                      Md3ListTile(
                        leading: const Icon(Icons.login_rounded),
                        title: const Text('论坛账号密码登录'),
                        subtitle: const Text(
                          '通过 forums.e-hentai.org 获取登录 Cookie',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _showEhPasswordLoginDialog,
                      ),
                      SwitchListTile(
                        contentPadding: switchTilePadding,
                        secondary: const Icon(Icons.translate_rounded),
                        title: const Text('E-Hentai 标签中文翻译'),
                        value: store.translateEhTags,
                        onChanged: store.setTranslateEhTags,
                      ),
                      Md3ListTile(
                        leading: const Icon(Icons.cloud_download_outlined),
                        title: const Text('中文标签词库'),
                        subtitle: Text(
                          translator.hasDatabase
                              ? '已加载 Mapaler 完整词库 (${translator.entryCount} 条)'
                              : '当前使用内置精选词库 (${translator.entryCount} 条)',
                          style: Md3Typography.tabularFigures(null),
                        ),
                        trailing: translator.isUpdating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : FilledButton.tonal(
                                onPressed: () async {
                                  final ok = await translator.downloadAndUpdate(
                                    widget.deps.httpClient.dio,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          ok
                                              ? '标签词库更新成功 (${translator.entryCount} 条)'
                                              : '更新失败: ${translator.lastError ?? ""}',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: const Text('更新词库'),
                              ),
                      ),
                    ],
                  ),

                  const Md3SectionHeader('外观与阅读器'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Md3Spacing.s16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('主题模式', style: theme.textTheme.labelLarge),
                          const SizedBox(height: Md3Spacing.s8),
                          PrismThemeModePicker(
                            value: store.themeMode,
                            seedColor:
                                HedoneTheme.seedColorFromId(store.themeSeedId),
                            amoledBlack: store.amoledBlack,
                            contrastLevel: store.contrastLevel,
                            floatingNavBar: store.floatingNavBar,
                            onChanged: store.setThemeMode,
                          ),
                          const SizedBox(height: Md3Spacing.s16),
                          Text('对比度档位', style: theme.textTheme.labelLarge),
                          const SizedBox(height: Md3Spacing.s8),
                          PrismSegmentedControl<double>(
                            value: normalizedContrast,
                            onChanged: store.setContrastLevel,
                            segments: const [
                              (0.0, '标准'),
                              (0.5, '中等'),
                              (1.0, '高'),
                            ],
                          ),
                          const SizedBox(height: Md3Spacing.s8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('悬浮胶囊导航栏'),
                            subtitle: const Text(
                              '开启时使用 FlClash 风格液态玻璃悬浮胶囊导航，关闭后宽屏切换为侧边栏',
                            ),
                            value: store.floatingNavBar,
                            onChanged: store.setFloatingNavBar,
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('AMOLED 纯黑背景'),
                            value: store.amoledBlack,
                            onChanged: store.setAmoledBlack,
                          ),
                          const SizedBox(height: Md3Spacing.s8),
                          Text(
                            'Material 3 主题色',
                            style: theme.textTheme.labelLarge,
                          ),
                          const SizedBox(height: Md3Spacing.s8),
                          Wrap(
                            spacing: Md3Spacing.s8,
                            runSpacing: Md3Spacing.s8,
                            children: HedoneTheme.presets.map((preset) {
                              return ChoiceChip(
                                selected: store.themeSeedId == preset.id,
                                avatar: CircleAvatar(
                                  backgroundColor: preset.color,
                                ),
                                label: Text(preset.name),
                                onSelected: (_) =>
                                    store.setThemeSeedId(preset.id),
                              );
                            }).toList(),
                          ),
                          const Divider(height: Md3Spacing.s24),
                          Text('默认阅读模式', style: theme.textTheme.labelLarge),
                          const SizedBox(height: Md3Spacing.s8),
                          Wrap(
                            spacing: Md3Spacing.s8,
                            runSpacing: Md3Spacing.s8,
                            children: ReaderMode.values.map((m) {
                              return ChoiceChip(
                                selected: store.defaultReaderMode == m,
                                label: Text(m.label),
                                onSelected: (_) =>
                                    store.setDefaultReaderMode(m),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: Md3Spacing.s8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('记录阅读历史与页码进度'),
                            value: store.keepHistory,
                            onChanged: store.setKeepHistory,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Md3SectionHeader('网络代理与缓存'),
                  Md3SegmentedListGroup(
                    children: [
                      Md3ListTile(
                        leading: const Icon(Icons.router_outlined),
                        title: const Text('HTTP 代理'),
                        subtitle: Text(
                          store.proxyAddress.isEmpty
                              ? '直连（未配置代理）'
                              : store.proxyAddress,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _showProxyDialog,
                      ),
                      SwitchListTile(
                        contentPadding: switchTilePadding,
                        secondary: const Icon(Icons.security_outlined),
                        title: const Text('忽略 TLS/HTTPS 证书校验'),
                        subtitle: const Text('用于兼容自签名代理或 CDN 镜像节点'),
                        value: store.allowBadCertificates,
                        onChanged: (v) =>
                            store.setNetworkConfig(allowBadCertificates: v),
                      ),
                      Md3ListTile(
                        leading: const Icon(Icons.cleaning_services_outlined),
                        title: const Text('清理图片缓存'),
                        subtitle: const Text('清除内存及 JM 反混淆磁盘缓存'),
                        onTap: () async {
                          clearHedoneImageMemoryCache();
                          final bytes = await JmImageDescrambler.clearCache();
                          if (context.mounted) {
                            final mb =
                                (bytes / (1024 * 1024)).toStringAsFixed(2);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('已清理图片缓存 ($mb MB)')),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
