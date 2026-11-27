import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/song.dart';
import '../../domain/state/favorites_state.dart';
import '../../domain/state/queue_state.dart';
import '../../domain/state/settings_state.dart';
import '../../services/player_controller.dart';
import '../now_playing/open_now_playing.dart';
import '../widgets/solara_ui.dart';
import '../widgets/song_row.dart';

class QueuePanel extends ConsumerStatefulWidget {
  /// 点歌后是否跳到播放页。
  ///
  /// 队列面板有两个宿主：播放页里的「播放队列」弹层（已经在那儿了，再 push 一层
  /// 就会叠出第二个播放页），和「我的 → 队列」弹层（离播放页还隔着一层，
  /// 点歌后停在原地会让人以为没反应）。由宿主自己决定。
  final bool openPlayer;

  /// 是否允许拖拽排序。播放页里的队列弹层高度有限、且主要用于「看」，
  /// 只给独立的一页开排序。
  final bool reorderable;

  const QueuePanel({
    super.key,
    this.openPlayer = false,
    this.reorderable = false,
  });

  @override
  ConsumerState<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends ConsumerState<QueuePanel> {
  final _scrollController = ScrollController();
  bool _didInitialScroll = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _confirmClear(BuildContext context, QueueStateNotifier queue) {
    final scheme = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('清空播放队列'),
            content: const Text('只清空列表，当前播放的歌会继续播放。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  queue.clear();
                  Navigator.pop(ctx);
                },
                child: Text('清空', style: TextStyle(color: scheme.error)),
              ),
            ],
          ),
    );
  }

  void _scrollToCurrentSong(int index) {
    if (!_scrollController.hasClients || index < 0) return;
    const itemHeight = 62.0;
    final viewport = _scrollController.position.viewportDimension;
    final target = (index * itemHeight) - (viewport / 2) + (itemHeight / 2);
    _scrollController.jumpTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final queueState = ref.watch(queueStateProvider);
    final queue = ref.read(queueStateProvider.notifier);
    final player = ref.read(playerControllerProvider.notifier);
    final playerState = ref.watch(playerControllerProvider);
    final settings = ref.watch(settingsStateProvider);
    final favorites = ref.read(favoritesStateProvider.notifier);

    if (queueState.songs.isEmpty) {
      return const EmptyState(
        icon: Icons.queue_music_rounded,
        title: '队列是空的',
        hint: '在任意歌曲上长按，选「加入队列」',
      );
    }

    if (!_didInitialScroll) {
      _didInitialScroll = true;
      final index = queueState.songs.indexWhere(
        (s) =>
            s.id == playerState.currentSong?.id &&
            s.source == playerState.currentSong?.source,
      );
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToCurrentSong(index),
      );
    }

    Widget buildRow(Song song, int index) {
      return SongRow(
        song: song,
        showArtwork: false,
        // 队列里的行不显示序号：序号本身会随排序变，写了反而干扰
        // 「拖到第几位」的判断。
        onTap: () {
          queue.selectSong(song);
          player.playSong(song, quality: settings.playbackQuality);
          // 在「我的 → 队列」里点歌：直接进播放页。
          // 这里不先 pop 弹层——把播放页压在上面，关掉播放页正好回到队列，
          // 用户想接着调下一首时不用重新点开。
          if (widget.openPlayer) openNowPlaying(context);
        },
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                favorites.isFavorite(song)
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color:
                    favorites.isFavorite(song)
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
              ),
              onPressed: () => favorites.toggleFavorite(song),
            ),
            IconButton(
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
              onPressed: () => queue.removeAt(index),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${queueState.songs.length} 首 · 正在播放第 '
                  '${queueState.currentIndex + 1} 首',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (widget.reorderable) ...[
                Text(
                  '长按拖动排序',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(width: 4),
                // 清空整条队列：QueueStateNotifier.clear() 一直存在，
                // 但界面上没有任何入口，队列只能一首一首删。
                IconButton(
                  iconSize: 17,
                  visualDensity: VisualDensity.compact,
                  tooltip: '清空队列',
                  icon: Icon(
                    Icons.delete_sweep_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                  onPressed: () => _confirmClear(context, queue),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child:
              widget.reorderable
                  ? ReorderableListView.builder(
                    scrollController: _scrollController,
                    padding: const EdgeInsets.only(bottom: 20),
                    buildDefaultDragHandles: false,
                    itemCount: queueState.songs.length,
                    // onReorderItem 的 newIndex 已经处理过「移除后前移」，
                    // 不用再手动减一。
                    onReorderItem: (oldIndex, newIndex) {
                      HapticFeedback.selectionClick();
                      queue.moveSong(oldIndex, newIndex);
                    },
                    itemBuilder:
                        (context, index) => ReorderableDelayedDragStartListener(
                          key: ValueKey(
                            '${queueState.songs[index].source}:'
                            '${queueState.songs[index].id}',
                          ),
                          index: index,
                          child: buildRow(queueState.songs[index], index),
                        ),
                  )
                  : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: queueState.songs.length,
                    itemBuilder:
                        (context, index) =>
                            buildRow(queueState.songs[index], index),
                  ),
        ),
      ],
    );
  }
}
