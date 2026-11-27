import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/models/user_playlist.dart';
import '../../domain/state/favorites_state.dart';
import '../../domain/state/history_state.dart';
import '../../domain/state/local_songs_state.dart';
import '../../domain/state/playlist_state.dart';
import '../../domain/state/queue_state.dart';
import '../../domain/state/settings_state.dart';
import '../../services/player_controller.dart';
import '../favorites/favorites_panel.dart';
import '../history/history_panel.dart';
import '../local/import_local_music.dart';
import '../local/local_songs_panel.dart';
import '../playlist/playlist_screen.dart';
import '../queue/queue_panel.dart';
import '../now_playing/open_now_playing.dart';
import '../widgets/cover_collage.dart';
import '../widgets/cover_image.dart';
import '../widgets/solara_ui.dart';

/// 我的音乐。
///
/// 版式：顶部一块渐变身份卡 + 四个统计入口，往下是「我的歌单」封面网格。
/// 统计入口用带渐变的方格而不是白底 Card：白卡在黑底上是一块块补丁，
/// 渐变色块则像一组彩色唱片，更接近网易云「我的」页的气质。
class MyScreen extends ConsumerStatefulWidget {
  const MyScreen({super.key});

  @override
  ConsumerState<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends ConsumerState<MyScreen> {
  void _showPanel(String title, Widget panel, {IconData? icon}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder:
          (ctx) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.74,
            maxChildSize: 0.94,
            minChildSize: 0.42,
            builder:
                (_, scrollController) => _PanelShell(
                  title: title,
                  icon: icon,
                  controller: scrollController,
                  child: panel,
                ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final favCount = ref.watch(favoritesStateProvider).favorites.length;
    final histCount = ref.watch(historyStateProvider).entries.length;
    final queueCount = ref.watch(queueStateProvider).songs.length;
    final localCount = ref.watch(localSongsProvider).length;
    final playlists = ref.watch(playlistStateProvider).playlists;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: false,
            floating: true,
            toolbarHeight: 60,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            title: const Text('我的音乐'),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProfileCard(
                  favCount: favCount,
                  playlistCount: playlists.length,
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _StatTile(
                        icon: Icons.favorite_rounded,
                        label: '收藏',
                        count: favCount,
                        colors: const [Color(0xFFFF5F6D), Color(0xFFFF8A5B)],
                        onTap:
                            () => _showPanel(
                              '我的收藏',
                              const FavoritesPanel(),
                              icon: Icons.favorite_rounded,
                            ),
                      ),
                      const SizedBox(width: 10),
                      _StatTile(
                        icon: Icons.history_rounded,
                        label: '历史',
                        count: histCount,
                        colors: const [Color(0xFF4F8CFF), Color(0xFF6FD5FF)],
                        onTap:
                            () => _showPanel(
                              '播放历史',
                              const HistoryPanel(),
                              icon: Icons.history_rounded,
                            ),
                      ),
                      const SizedBox(width: 10),
                      _StatTile(
                        icon: Icons.queue_music_rounded,
                        label: '队列',
                        count: queueCount,
                        colors: const [Color(0xFF35D6A4), Color(0xFF7CE8A8)],
                        onTap:
                            () => _showPanel(
                              '播放队列',
                              const QueuePanel(
                                openPlayer: true,
                                reorderable: true,
                              ),
                              icon: Icons.queue_music_rounded,
                            ),
                      ),
                      const SizedBox(width: 10),
                      _StatTile(
                        icon: Icons.folder_rounded,
                        label: '本地',
                        count: localCount,
                        colors: const [Color(0xFFFFB347), Color(0xFFFFD96B)],
                        onTap:
                            () => _showPanel(
                              '本地音乐',
                              const LocalSongsPanel(),
                              icon: Icons.folder_rounded,
                            ),
                        onLongPress:
                            () =>
                                importLocalMusic(context, ref, playFirst: true),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: SectionHeader(
              title: '我的歌单',
              subtitle: playlists.isEmpty ? null : '${playlists.length} 个歌单',
              trailing: _NewPlaylistButton(),
            ),
          ),
          if (playlists.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: EmptyState(
                  icon: Icons.library_music_rounded,
                  title: '还没有歌单',
                  hint: '点右上角「新建」开始整理你的收藏',
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.82,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 16,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      _PlaylistCard(playlist: playlists[index], index: index),
                  childCount: playlists.length,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }
}

// ── 身份卡 ───────────────────────────────────────────────
class _ProfileCard extends StatelessWidget {
  final int favCount;
  final int playlistCount;
  const _ProfileCard({required this.favCount, required this.playlistCount});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary.withValues(alpha: 0.22),
              SolaraColors.brandAlt.withValues(alpha: 0.14),
              scheme.surfaceContainerLow,
            ],
          ),
          borderRadius: SolaraRadius.cardRadius,
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: SolaraColors.sunset,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: SolaraColors.brand.withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.graphic_eq_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 15),
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
                  const SizedBox(height: 3),
                  Text(
                    '$favCount 首收藏 · $playlistCount 个歌单',
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
      ),
    );
  }
}

// ── 统计入口 ─────────────────────────────────────────────
class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final List<Color> colors;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.count,
    required this.colors,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tint = colors.first;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
          decoration: BoxDecoration(
            // 四块高饱和彩色方块并排放，会像游戏面板而不是音乐 App。
            // 底色只留极淡的一层同色晕染，颜色全部集中在图标上。
            color:
                isDark
                    ? Color.alphaBlend(
                      tint.withValues(alpha: 0.06),
                      scheme.surfaceContainerLow,
                    )
                    : Color.alphaBlend(
                      tint.withValues(alpha: 0.05),
                      Colors.white,
                    ),
            borderRadius: SolaraRadius.cardRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: tint, size: 19),
              const SizedBox(height: 10),
              Text(
                '$count',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 歌单卡 ───────────────────────────────────────────────
class _PlaylistCard extends ConsumerWidget {
  final UserPlaylist playlist;
  final int index;
  const _PlaylistCard({required this.playlist, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final covers =
        playlist.songs
            .map((s) => s.picUrl ?? '')
            .where((u) => u.isNotEmpty)
            .take(4)
            .toList();

    return GestureDetector(
      onTap:
          () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PlaylistDetailScreen(playlist: playlist),
            ),
          ),
      onLongPress: () => _showMenu(context, ref),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: SolaraRadius.tileRadius,
              child:
                  covers.isNotEmpty
                      ? CoverCollage(urls: covers)
                      : CoverImage(
                        url: '',
                        borderRadius: BorderRadius.zero,
                        fallbackIcon: Icons.queue_music_rounded,
                        fallbackIconSize: 34,
                        background: _tint(index),
                      ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            playlist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${playlist.songs.length} 首',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  static Color _tint(int i) {
    const palette = [
      Color(0xFF7C6BFF),
      Color(0xFFFF7A45),
      Color(0xFF35D6A4),
      Color(0xFFFFC24B),
      Color(0xFF4F8CFF),
    ];
    return palette[i % palette.length].withValues(alpha: 0.26);
  }

  void _showMenu(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  _SheetAction(
                    icon: Icons.play_arrow_rounded,
                    label: '全部播放',
                    onTap: () {
                      if (playlist.songs.isEmpty) {
                        Navigator.pop(ctx);
                        return;
                      }
                      ref
                          .read(queueStateProvider.notifier)
                          .replaceQueue(playlist.songs, playlist.songs.first);
                      ref
                          .read(playerControllerProvider.notifier)
                          .playSong(
                            playlist.songs.first,
                            quality:
                                ref.read(settingsStateProvider).playbackQuality,
                          );
                      Navigator.pop(ctx);
                      openNowPlaying(context);
                    },
                  ),
                  _SheetAction(
                    icon: Icons.delete_outline_rounded,
                    label: '删除歌单',
                    danger: true,
                    onTap: () {
                      Navigator.pop(ctx);
                      ref
                          .read(playlistStateProvider.notifier)
                          .deletePlaylist(playlist.id);
                    },
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = danger ? scheme.error : scheme.onSurface;
    return Material(
      color: Colors.transparent,
      borderRadius: SolaraRadius.tileRadius,
      child: InkWell(
        borderRadius: SolaraRadius.tileRadius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewPlaylistButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => showCreatePlaylistDialog(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 15, color: scheme.primary),
            const SizedBox(width: 4),
            Text(
              '新建',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 面板外壳 ─────────────────────────────────────────────
class _PanelShell extends StatelessWidget {
  final String title;
  final IconData? icon;
  final ScrollController controller;
  final Widget child;

  const _PanelShell({
    required this.title,
    required this.controller,
    required this.child,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
              ],
              Text(
                title,
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
