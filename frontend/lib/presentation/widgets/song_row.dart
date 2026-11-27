import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/song.dart';
import '../../domain/state/favorites_state.dart';
import '../../services/player_controller.dart';
import 'song_actions.dart';
import 'playing_indicator.dart';
import 'song_artwork.dart';

/// 统一的歌曲行。
///
/// 搜索结果、歌单详情、榜单详情、收藏、历史、队列此前各写了一份
/// ListTile，字号、封面圆角、正在播放高亮全不一样。这里收成一份：
///  - 左侧封面（可选序号）+ 右侧两行文字，行高 64；
///  - 正在播放的行用一条竖着的强调条 + 橙色标题，而不是整块底色；
///  - 尾部的「更多」按钮收进弹出菜单，减少每行的视觉噪音。
class SongRow extends ConsumerWidget {
  final int? index;
  final Song song;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showArtwork;
  final bool showFavoriteAction;
  final bool showMore;
  final EdgeInsets padding;

  /// 长按整行时调用。为空则退回统一的歌曲菜单（收藏 / 队列 / 歌单 / MV）。
  final VoidCallback? onLongPress;

  const SongRow({
    super.key,
    required this.song,
    this.index,
    this.onTap,
    this.trailing,
    this.showArtwork = true,
    this.showFavoriteAction = true,
    this.showMore = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final playerState = ref.watch(
      playerControllerProvider.select(
        (s) => (s.currentSong?.id, s.currentSong?.source, s.isPlaying),
      ),
    );
    final isCurrent =
        playerState.$1 == song.id && playerState.$2 == song.source;
    final isPlaying = isCurrent && playerState.$3;
    final isFav = ref
        .watch(favoritesStateProvider)
        .favorites
        .any((s) => s.id == song.id && s.source == song.source);

    final textColor = isCurrent ? scheme.primary : scheme.onSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap:
            onTap == null
                ? null
                : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
        onLongPress: () {
          // 长按是「打开操作菜单」，给一次比点按更重的反馈，
          // 手感上才能区分这两个动作。
          HapticFeedback.mediumImpact();
          (onLongPress ?? () => showSongActions(context, ref, song))();
        },
        splashColor: scheme.primary.withValues(alpha: 0.06),
        highlightColor: scheme.primary.withValues(alpha: 0.04),
        child: Padding(
          padding: padding.copyWith(top: 7, bottom: 7),
          child: Row(
            children: [
              // 序号列：榜单/歌单里显示名次，正在播放时换成跳动频谱
              if (index != null)
                SizedBox(
                  width: 30,
                  child: Center(
                    child:
                        isCurrent
                            ? PlayingIndicator(
                              isPlaying: isPlaying,
                              color: scheme.primary,
                              size: 14,
                            )
                            : Text(
                              '${index! + 1}',
                              style: TextStyle(
                                fontSize: index! < 3 ? 14.5 : 12.5,
                                fontWeight:
                                    index! < 3
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                color:
                                    index! < 3
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                              ),
                            ),
                  ),
                ),
              if (showArtwork)
                SongArtwork(
                  picId: song.picId,
                  source: song.source,
                  picUrl: song.picUrl,
                  size: 48,
                  iconSize: 18,
                )
              else if (index == null)
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: PlayingIndicator(
                      isPlaying: isPlaying,
                      color: scheme.primary,
                      size: 16,
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      song.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            isCurrent ? FontWeight.w700 : FontWeight.w500,
                        color: textColor,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      song.album.isEmpty
                          ? song.artist
                          : '${song.artist} · ${song.album}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (showMore)
                _MoreButton(song: song, isFav: isFav),
              if (!showMore && showFavoriteAction && trailing == null)
                _FavoriteButton(song: song, isFav: isFav),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoriteButton extends ConsumerWidget {
  final Song song;
  final bool isFav;
  const _FavoriteButton({required this.song, required this.isFav});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      splashRadius: 18,
      icon: Icon(
        isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: isFav ? scheme.primary : scheme.onSurfaceVariant,
      ),
      onPressed: () {
        HapticFeedback.lightImpact();
        ref.read(favoritesStateProvider.notifier).toggleFavorite(song);
      },
    );
  }
}

class _MoreButton extends ConsumerWidget {
  final Song song;
  final bool isFav;
  const _MoreButton({required this.song, required this.isFav});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // 统一走长按菜单：菜单内容一致，才不会出现「有的页面能加歌单、
    // 有的页面只能收藏」这种按页面变的能力差异。
    return IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: 20,
      splashRadius: 18,
      icon: Icon(Icons.more_horiz_rounded, color: scheme.onSurfaceVariant),
      onPressed: () => showSongActions(context, ref, song),
    );
  }
}
