import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/discover.dart';
import '../../domain/models/song.dart';
import '../../domain/state/discover_state.dart';
import '../../domain/state/favorites_state.dart';
import '../../domain/state/queue_state.dart';
import '../../domain/state/settings_state.dart';
import '../../services/debug_log_bus.dart';
import '../../services/player_controller.dart';
import '../now_playing/open_now_playing.dart';
import '../widgets/cover_collage.dart';
import '../widgets/cover_image.dart';
import '../widgets/solara_ui.dart';
import '../widgets/song_actions.dart';
import '../widgets/song_row.dart';

/// 歌单详情页。
class SongListDetailScreen extends ConsumerStatefulWidget {
  final SongListItem item;
  final String source;

  const SongListDetailScreen({
    super.key,
    required this.item,
    required this.source,
  });

  @override
  ConsumerState<SongListDetailScreen> createState() =>
      _SongListDetailScreenState();
}

class _SongListDetailScreenState extends ConsumerState<SongListDetailScreen> {
  final _scrollController = ScrollController();
  List<Song> _songs = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
      _hasMore = true;
    });
    try {
      final songs = await ref
          .read(discoverStateProvider.notifier)
          .fetchSongListDetail(
            id: widget.item.id,
            source: widget.source,
            page: 1,
          );
      if (!mounted) return;
      setState(() {
        _songs = songs;
        _hasMore = songs.length >= 30;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final songs = await ref
          .read(discoverStateProvider.notifier)
          .fetchSongListDetail(
            id: widget.item.id,
            source: widget.source,
            page: nextPage,
          );
      if (!mounted) return;
      setState(() {
        _songs = [..._songs, ...songs];
        _page = nextPage;
        _hasMore = songs.length >= 30;
      });
    } catch (e) {
      DebugLogBus.add('[Discover] 歌单详情 加载更多失败: $e');
    }
    if (mounted) setState(() => _loadingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsStateProvider);
    final player = ref.read(playerControllerProvider.notifier);
    final queue = ref.read(queueStateProvider.notifier);
    final favorites = ref.read(favoritesStateProvider.notifier);

    final covers =
        widget.item.coverUrls.isNotEmpty
            ? widget.item.coverUrls
            : _songs
                .map((s) => s.picUrl ?? '')
                .where((u) => u.isNotEmpty)
                .take(4)
                .toList();
    final cover = widget.item.coverUrl ?? '';

    return Scaffold(
      body: RefreshIndicator(
        color: scheme.primary,
        onRefresh: _load,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverAppBar(
              expandedHeight: 250,
              pinned: true,
              backgroundColor: scheme.surface,
              surfaceTintColor: Colors.transparent,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                title: Text(
                  widget.item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (covers.isNotEmpty)
                      CoverCollage(urls: covers)
                    else if (cover.isNotEmpty)
                      CoverImage(
                        url: cover,
                        borderRadius: BorderRadius.zero,
                        fallbackIcon: Icons.queue_music_rounded,
                        fallbackIconSize: 44,
                      )
                    else
                      ColoredBox(color: scheme.surfaceContainerHigh),
                    const ScrimOverlay(start: 0.15, color: Color(0xF2000000)),
                  ],
                ),
              ),
            ),
            // 元信息 + 播放入口
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.item.author.isNotEmpty ||
                        (widget.item.playCount ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          [
                            if (widget.item.author.isNotEmpty)
                              widget.item.author,
                            if ((widget.item.playCount ?? '').isNotEmpty)
                              '${widget.item.playCount} 次播放',
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if ((widget.item.description ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          widget.item.description!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.45,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (_songs.isNotEmpty)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: Text('播放全部（${_songs.length}）'),
                          onPressed: () {
                            queue.replaceQueue(_songs, _songs.first);
                            player.playSong(
                              _songs.first,
                              quality: settings.playbackQuality,
                            );
                            openNowPlaying(context);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: '加载失败',
                  hint: _error,
                  action: FilledButton(
                    onPressed: _load,
                    child: const Text('重试'),
                  ),
                ),
              )
            else if (_songs.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.music_off_rounded,
                  title: '这个歌单暂时没有歌曲',
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final song = _songs[index];
                  return SongRow(
                    song: song,
                    index: index,
                    showArtwork: false,
                    onLongPress: () => showSongActions(context, ref, song),
                    onTap: () {
                      queue.replaceQueue(_songs, song);
                      player.playSong(song, quality: settings.playbackQuality);
                      // 点歌即进播放页：在列表里选一首歌，用户想做的下一件事
                      // 通常是看歌词/调音质，而不是继续盯着这张列表。
                      openNowPlaying(context);
                    },
                    trailing: IconButton(
                      iconSize: 19,
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
                  );
                }, childCount: _songs.length),
              ),
            if (_loadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}
