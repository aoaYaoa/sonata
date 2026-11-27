import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/models/music_source.dart';
import '../../domain/models/playback_quality.dart';
import '../../domain/state/settings_state.dart';
import '../../services/player_controller.dart';
import '../../services/cookie_service.dart';
import '../../services/app_config.dart';
import '../../services/debug_log_bus.dart';
import '../../services/providers.dart';
import '../../data/providers.dart';

/// 设置页。
///
/// 结构：分组标题用大写字距的小标签，组内是圆角卡 + 分隔线，
/// 每行左侧一个带色底的图标。比 Material 默认的 ListTile 列表更有层次，
/// 也是网易云/QQ 音乐设置页的通用做法。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsStateProvider);
    final notifier = ref.read(settingsStateProvider.notifier);
    final timerState = ref.watch(sleepTimerWithPlayerProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            toolbarHeight: 60,
            title: const Text('设置'),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _AppBanner(),
                  const SizedBox(height: 26),

                  const _GroupLabel('外观'),
                  _SettingsCard(
                    children: [
                      _SettingsTile(
                        icon: Icons.contrast_rounded,
                        iconColor: const Color(0xFF9B7BFF),
                        title: '主题模式',
                        subtitle: _themeLabel(settings.themeMode),
                        trailing: _ThemeSegment(
                          current: settings.themeMode,
                          onChanged: notifier.setThemeMode,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  const _GroupLabel('播放'),
                  _SettingsCard(
                    children: [
                      _SettingsTile(
                        icon: Icons.high_quality_rounded,
                        iconColor: const Color(0xFF4F8CFF),
                        title: '播放音质',
                        subtitle: _qualityLabel(settings.playbackQuality),
                        onTap:
                            () => _showQualitySheet(
                              context,
                              settings.playbackQuality,
                              notifier,
                              ref,
                            ),
                      ),
                      const _Divider(),
                      _SettingsTile(
                        icon: Icons.travel_explore_rounded,
                        iconColor: const Color(0xFFFF9A5C),
                        title: '音乐来源',
                        subtitle: _sourceLabel(settings.searchSource),
                        onTap:
                            () => _showPickerSheet(
                              context: context,
                              title: '音乐来源',
                              items: {
                                for (final id in MusicSource.ids)
                                  id: MusicSource.fullLabel(id),
                              },
                              current: settings.searchSource,
                              onSelect: notifier.setSearchSource,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  const _GroupLabel('睡眠定时器'),
                  _SettingsCard(
                    children: [
                      _SettingsTile(
                        icon: Icons.bedtime_rounded,
                        iconColor: const Color(0xFF6C7BFF),
                        title: '定时关闭',
                        subtitle:
                            timerState.active && timerState.remaining != null
                                ? _formatRemaining(timerState.remaining!)
                                : '未启用',
                        subtitleColor:
                            timerState.active ? scheme.primary : null,
                        trailing:
                            timerState.active
                                ? _CancelChip(
                                  onTap:
                                      () =>
                                          ref
                                              .read(
                                                sleepTimerWithPlayerProvider
                                                    .notifier,
                                              )
                                              .cancel(),
                                )
                                : null,
                        onTap:
                            timerState.active
                                ? null
                                : () => _showSleepTimerSheet(context, ref),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  const _GroupLabel('Cookie 管理'),
                  const _CookieSection(),
                  const SizedBox(height: 22),

                  const _GroupLabel('同步'),
                  const _SyncSection(),
                  const SizedBox(height: 22),

                  const _GroupLabel('存储'),
                  const _StorageSection(),
                  const SizedBox(height: 22),

                  const _GroupLabel('开发者'),
                  _SettingsCard(
                    children: [
                      _SettingsTile(
                        icon: Icons.bug_report_rounded,
                        iconColor: const Color(0xFFFF5F6D),
                        title: '调试模式',
                        subtitle: '在播放条下方显示日志控制台',
                        trailing: Switch(
                          value: settings.debugMode,
                          onChanged: notifier.setDebugMode,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  const _GroupLabel('关于'),
                  const _AboutCard(),
                  const SizedBox(height: 36),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _themeLabel(String mode) {
    switch (mode) {
      case 'light':
        return '浅色';
      case 'dark':
        return '深色';
      default:
        return '跟随系统';
    }
  }

  static String _qualityLabel(String q) => PlaybackQuality.label(q);

  static String _sourceLabel(String s) => MusicSource.fullLabel(s);

  static String _formatRemaining(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (m > 0) return '剩余 $m 分 ${s.toString().padLeft(2, '0')} 秒';
    return '剩余 $s 秒';
  }

  void _showQualitySheet(
    BuildContext context,
    String current,
    SettingsStateNotifier notifier,
    WidgetRef ref,
  ) {
    final controller = ref.read(playerControllerProvider.notifier);
    _showPickerSheet(
      context: context,
      title: '播放音质',
      // 档位表与播放页共用 [PlaybackQuality]：原来设置页固定列 4 档，
      // 在 QQ 匿名态里选「无损」根本拿不到，白等一次失败。
      items: {
        for (final q in PlaybackQuality.availableFor(controller.currentSong))
          q: PlaybackQuality.label(q),
      },
      current: current,
      onSelect: (quality) {
        notifier.setPlaybackQuality(quality);
        // 设置页也能立刻生效：不重载的话，用户改完音质回到播放页
        // 听到的还是旧流，「切换音质」形同虚设。
        controller.applyQuality(quality).ignore();
      },
    );
  }

  void _showSleepTimerSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '睡眠定时器',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 9,
                    runSpacing: 9,
                    children: [
                      for (final entry
                          in const {
                            '15 分钟': Duration(minutes: 15),
                            '30 分钟': Duration(minutes: 30),
                            '45 分钟': Duration(minutes: 45),
                            '1 小时': Duration(hours: 1),
                            '1.5 小时': Duration(minutes: 90),
                            '2 小时': Duration(hours: 2),
                          }.entries)
                        ActionChip(
                          label: Text(entry.key),
                          onPressed: () {
                            ref
                                .read(sleepTimerWithPlayerProvider.notifier)
                                .start(entry.value);
                            Navigator.pop(ctx);
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );
  }

  void _showPickerSheet({
    required BuildContext context,
    required String title,
    required Map<String, String> items,
    required String current,
    required ValueChanged<String> onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 8),
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                for (final entry in items.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Material(
                      color:
                          current == entry.key
                              ? scheme.primary.withValues(alpha: 0.12)
                              : Colors.transparent,
                      borderRadius: SolaraRadius.tileRadius,
                      child: InkWell(
                        borderRadius: SolaraRadius.tileRadius,
                        onTap: () {
                          onSelect(entry.key);
                          Navigator.pop(ctx);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Text(
                                entry.value,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight:
                                      current == entry.key
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                  color:
                                      current == entry.key
                                          ? scheme.primary
                                          : scheme.onSurface,
                                ),
                              ),
                              const Spacer(),
                              if (current == entry.key)
                                Icon(
                                  Icons.check_rounded,
                                  size: 19,
                                  color: scheme.primary,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── 顶部品牌卡 ────────────────────────────────────────────
class _AppBanner extends StatelessWidget {
  const _AppBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.24),
            SolaraColors.violet.withValues(alpha: 0.16),
            scheme.surfaceContainerLow,
          ],
        ),
        borderRadius: SolaraRadius.cardRadius,
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: SolaraColors.sunset,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Solara',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '音乐，随心所至',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 主题分段控件 ──────────────────────────────────────────
class _ThemeSegment extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;
  const _ThemeSegment({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const options = [
      ('system', Icons.brightness_auto_rounded),
      ('light', Icons.light_mode_rounded),
      ('dark', Icons.dark_mode_rounded),
    ];
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children:
            options.map((opt) {
              final selected = current == opt.$1;
              return GestureDetector(
                onTap: () => onChanged(opt.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: selected ? scheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    opt.$2,
                    size: 16,
                    color:
                        selected
                            ? SolaraColors.onAccent(scheme.primary)
                            : scheme.onSurfaceVariant,
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }
}

class _CancelChip extends StatelessWidget {
  final VoidCallback onTap;
  const _CancelChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: scheme.error.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '取消',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: scheme.error,
          ),
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String title;
  const _GroupLabel(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 9),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: SolaraRadius.cardRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 58),
      child: Divider(
        height: 1,
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: 0.6),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: iconColor),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          color: subtitleColor ?? scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Cookie 管理 ──────────────────────────────────────────
class _CookieSection extends ConsumerStatefulWidget {
  const _CookieSection();

  @override
  ConsumerState<_CookieSection> createState() => _CookieSectionState();
}

class _CookieSectionState extends ConsumerState<_CookieSection> {
  Map<String, CookieStatus> _status = {};
  String? _loadingType;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
  }

  Future<void> _fetchStatus() async {
    try {
      final svc = ref.read(cookieServiceProvider);
      final s = await svc.fetchStatus();
      if (mounted) setState(() => _status = s);
    } catch (e) {
      DebugLogBus.add('[Settings] 获取 Cookie 状态失败: $e');
    }
  }

  Future<void> _upload(String type) async {
    setState(() => _loadingType = type);
    try {
      final svc = ref.read(cookieServiceProvider);
      final result = await svc.uploadCookie(type);
      if (result == null) return;
      if (mounted) {
        setState(() => _status = {..._status, type: result});
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('上传成功')));
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('上传失败: $msg')));
      }
    } finally {
      if (mounted) setState(() => _loadingType = null);
    }
  }

  Color _statusColor(CookieStatus? s, ColorScheme cs) {
    if (s == null || !s.exists) return cs.onSurfaceVariant;
    if (s.isExpired) return cs.error;
    final days = s.daysUntilExpiry;
    if (days != null && days <= 1) return SolaraColors.amber;
    return SolaraColors.mint;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final yt = _status['youtube'];
    final bili = _status['bilibili'];
    return _SettingsCard(
      children: [
        _SettingsTile(
          icon: Icons.smart_display_rounded,
          iconColor: const Color(0xFFFF5F6D),
          title: 'YouTube Cookie',
          subtitle: yt?.label ?? '加载中…',
          subtitleColor: _statusColor(yt, cs),
          trailing:
              _loadingType == 'youtube'
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : null,
          onTap: _loadingType != null ? null : () => _upload('youtube'),
        ),
        const _Divider(),
        _SettingsTile(
          icon: Icons.ondemand_video_rounded,
          iconColor: const Color(0xFF4FACFE),
          title: 'B站 Cookie',
          subtitle: bili?.label ?? '加载中…',
          subtitleColor: _statusColor(bili, cs),
          trailing:
              _loadingType == 'bilibili'
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : null,
          onTap: _loadingType != null ? null : () => _upload('bilibili'),
        ),
      ],
    );
  }
}

// ── 同步状态 ────────────────────────────────────────────────
class _SyncSection extends ConsumerWidget {
  const _SyncSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final sync = ref.watch(syncControllerProvider);
    // ChangeNotifier 没有 Riverpod 的 listen 通道，用 ListenableBuilder
    // 直接盯它自己的 notifyListeners。
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final error = sync.lastError;
        final last = sync.lastSyncedAt;
        final String subtitle;
        if (error != null) {
          subtitle = '同步失败：$error';
        } else if (sync.syncing) {
          subtitle = '正在同步…';
        } else if (last != null) {
          subtitle = '上次同步 ${_agoLabel(last)}';
        } else {
          subtitle = '尚未同步';
        }
        return _SettingsCard(
          children: [
            _SettingsTile(
              icon: Icons.cloud_sync_rounded,
              iconColor: const Color(0xFF4FB0FF),
              title: '队列 / 收藏 / 歌单',
              subtitle: subtitle,
              subtitleColor: error != null ? scheme.error : null,
              trailing:
                  sync.syncing
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : null,
              onTap:
                  sync.syncing
                      ? null
                      : () => ref.read(syncControllerProvider).syncNow(),
            ),
          ],
        );
      },
    );
  }

  static String _agoLabel(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inMinutes < 60) return '${d.inMinutes} 分钟前';
    if (d.inHours < 24) return '${d.inHours} 小时前';
    return '${d.inDays} 天前';
  }
}

// ── 存储与缓存 ──────────────────────────────────────────────
class _StorageSection extends StatelessWidget {
  const _StorageSection();

  void _clearCoverCache(BuildContext context) {
    // 封面走 Image.network 的内存缓存，清掉后下次进页面会重新拉。
    imageCache.clear();
    imageCache.clearLiveImages();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('封面缓存已清空')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cacheCount = imageCache.currentSize;
    return _SettingsCard(
      children: [
        _SettingsTile(
          icon: Icons.image_rounded,
          iconColor: const Color(0xFF9B7BFF),
          title: '清除封面缓存',
          // 报一下当前占了多少张：只写「清除」用户不知道清了多少东西。
          subtitle: cacheCount == 0 ? '当前没有缓存' : '当前缓存 $cacheCount 张封面',
          onTap: () => _clearCoverCache(context),
        ),
        const _Divider(),
        _SettingsTile(
          icon: Icons.cloud_outlined,
          iconColor: scheme.onSurfaceVariant,
          title: '后端地址',
          subtitle: AppConfig.baseUrl,
        ),
      ],
    );
  }
}

// ── 关于 ────────────────────────────────────────────────────
class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _SettingsCard(
      children: [
        _SettingsTile(
          icon: Icons.info_outline_rounded,
          iconColor: const Color(0xFF6C7BFF),
          title: 'Solara',
          subtitle: '版本 ${AppConfig.version} · 构建 ${AppConfig.buildNumber}',
        ),
        const _Divider(),
        _SettingsTile(
          icon: Icons.music_note_rounded,
          iconColor: scheme.primary,
          title: '音源',
          subtitle: MusicSource.ids.map(MusicSource.shortLabel).join(' / '),
        ),
      ],
    );
  }
}
