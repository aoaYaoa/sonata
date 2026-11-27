import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/models/song.dart';
import '../../domain/state/favorites_state.dart';
import '../../domain/state/queue_state.dart';
import '../../domain/state/settings_state.dart';
import '../../services/player_controller.dart';
import '../now_playing/mv_player_screen.dart';
import '../now_playing/open_now_playing.dart';
import '../playlist/add_to_playlist_sheet.dart';

/// 歌曲长按菜单。
///
/// 之前只有 SongRow 右上角的「更多」弹出三个动作（收藏 / 加入队列 / 立即播放），
/// 而且大部分列表（歌单详情、榜单详情、收藏、历史、队列）压根没打开
/// `showMore`，那些页面上除了「点一下播放」之外什么都做不了——
/// 想收藏一首歌只能先进播放页，想加入歌单更是不可能（「添加到歌单」弹层
/// 写好了却没人调用）。
///
/// 现在统一由长按触发，动作按「这一行能做什么」自动裁剪：
/// 没有 mvId 就不出现「播放 MV」，本地歌曲不出现「添加到歌单」以外的网络动作。
Future<void> showSongActions(
  BuildContext context,
  WidgetRef ref,
  Song song, {

  /// 传了就在删除动作里带上「从当前列表移除」。
  VoidCallback? onRemove,
  String? removeLabel,
}) {
  final isFav = ref
      .read(favoritesStateProvider)
      .favorites
      .any((s) => s.id == song.id && s.source == song.source);

  return showModalBottomSheet<void>(
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
                    color: Theme.of(
                      ctx,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                _SongHeader(song: song),
                const SizedBox(height: 6),
                _Action(
                  icon: Icons.play_arrow_rounded,
                  label: '立即播放',
                  onTap: () {
                    Navigator.pop(ctx);
                    // 单曲播放也要进队列，否则播完这一首队列里没有它，
                    // 「下一首」会跳到一首风马牛不相及的歌。
                    ref.read(queueStateProvider.notifier).addSong(song);
                    ref
                        .read(playerControllerProvider.notifier)
                        .playSong(
                          song,
                          quality:
                              ref.read(settingsStateProvider).playbackQuality,
                        );
                    openNowPlaying(context);
                  },
                ),
                _Action(
                  icon:
                      isFav
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                  label: isFav ? '取消收藏' : '收藏',
                  onTap: () {
                    Navigator.pop(ctx);
                    ref
                        .read(favoritesStateProvider.notifier)
                        .toggleFavorite(song);
                  },
                ),
                _Action(
                  icon: Icons.playlist_play_rounded,
                  label: '下一首播放',
                  onTap: () {
                    Navigator.pop(ctx);
                    ref.read(queueStateProvider.notifier).insertNext(song);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('下一首播放：${song.name}')),
                    );
                  },
                ),
                _Action(
                  icon: Icons.queue_music_rounded,
                  label: '加入队列',
                  onTap: () {
                    Navigator.pop(ctx);
                    ref.read(queueStateProvider.notifier).addSong(song);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已加入队列：${song.name}')),
                    );
                  },
                ),
                if (song.source != 'local')
                  _Action(
                    icon: Icons.playlist_add_rounded,
                    label: '添加到歌单',
                    onTap: () {
                      Navigator.pop(ctx);
                      showAddToPlaylistSheet(context, song: song);
                    },
                  ),
                if ((song.mvId ?? '').isNotEmpty)
                  _Action(
                    icon: Icons.video_library_outlined,
                    label: '播放 MV',
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder:
                              (_) => MvPlayerScreen(
                                mvId: song.mvId!,
                                source: song.source,
                                songName: song.name,
                                artist: song.artist,
                              ),
                        ),
                      );
                    },
                  ),
                if (onRemove != null)
                  _Action(
                    icon: Icons.remove_circle_outline_rounded,
                    label: removeLabel ?? '从列表移除',
                    danger: true,
                    onTap: () {
                      Navigator.pop(ctx);
                      onRemove();
                    },
                  ),
              ],
            ),
          ),
        ),
  );
}

class _SongHeader extends StatelessWidget {
  final Song song;
  const _SongHeader({required this.song});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            song.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            song.album.isEmpty ? song.artist : '${song.artist} · ${song.album}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const _Action({
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: danger ? color : scheme.onSurfaceVariant,
              ),
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
