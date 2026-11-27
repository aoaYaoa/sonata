import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/models/music_source.dart';
import '../../domain/models/song.dart';
import '../../domain/state/history_state.dart';
import '../../domain/state/home_music_hall_state.dart';
import '../../domain/state/queue_state.dart';
import '../../domain/state/search_state.dart';
import '../../domain/state/settings_state.dart';
import '../../services/player_controller.dart';
import '../discover/all_leaderboards_screen.dart';
import '../history/history_screen.dart';
import '../now_playing/open_now_playing.dart';
import '../widgets/leaderboard_card.dart';
import '../widgets/solara_ui.dart';
import '../widgets/source_picker.dart';
import '../widgets/song_artwork.dart';
import '../widgets/song_actions.dart';
import '../widgets/song_row.dart';

/// 首页 / 搜索。
///
/// 版式参考网易云与 Spotify 的首页：顶部一块渐变气氛区放问候语和搜索框，
/// 往下是「最近播放」的横排小卡与「音乐馆」的两列封面网格。
/// 搜索框本身是入口，结果以覆盖层浮在内容上方，不跳页。
class SearchPanel extends ConsumerStatefulWidget {
  const SearchPanel({super.key});

  @override
  ConsumerState<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends ConsumerState<SearchPanel> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = ref.read(settingsStateProvider);
      ref.read(searchStateProvider.notifier).setSource(s.searchSource);
      ref
          .read(homeMusicHallStateProvider.notifier)
          .ensureLoaded(source: s.searchSource);
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(searchStateProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // 音源名统一从 MusicSource 取（以前 5 个页面各写一份 switch）。
  String _sourceLabel(String source) => MusicSource.shortLabel(source);

  @override
  Widget build(BuildContext context) {
    ref.listen<SettingsState>(settingsStateProvider, (prev, next) {
      if (prev?.searchSource != next.searchSource) {
        ref.read(searchStateProvider.notifier).setSource(next.searchSource);
        ref
            .read(homeMusicHallStateProvider.notifier)
            .load(source: next.searchSource);
      }
    });

    final searchState = ref.watch(searchStateProvider);
    final notifier = ref.read(searchStateProvider.notifier);
    final player = ref.read(playerControllerProvider.notifier);
    final playerState = ref.watch(playerControllerProvider);
    final settings = ref.watch(settingsStateProvider);
    final settingsNotifier = ref.read(settingsStateProvider.notifier);
    final queue = ref.read(queueStateProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    // 「搜过」也算浮层可见：搜不到结果时要让面板显示「没有找到」，
    // 否则浮层直接消失、露出首页，看起来像点了没反应。
    final overlayVisible =
        searchState.searched ||
        searchState.results.isNotEmpty ||
        searchState.error != null ||
        searchState.loading;

    return Scaffold(
      body: Stack(
        children: [
          _buildHomeContent(notifier),
          if (overlayVisible)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  notifier.clearResults();
                  _focusNode.unfocus();
                },
                child: Container(color: Colors.black.withValues(alpha: 0.28)),
              ),
            ),
          // 搜索框永远浮在最上面，结果面板贴在它下面
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SearchField(
                          controller: _controller,
                          focusNode: _focusNode,
                          loading: searchState.loading,
                          onChanged: () => setState(() {}),
                          onSubmitted: (value) {
                            if (value.trim().isEmpty) return;
                            notifier.search(value.trim());
                            _focusNode.unfocus();
                          },
                          onClear: () {
                            _controller.clear();
                            notifier.clearResults();
                          },
                        ),
                      ),
                      const SizedBox(width: 9),
                      SourcePill(
                        label: _sourceLabel(searchState.source),
                        elevated: true,
                        onTap:
                            () => showSourceSheet(
                              context,
                              current: searchState.source,
                              onSelected: (value) {
                                notifier.setSource(value);
                                settingsNotifier.setSearchSource(value);
                                // 已经搜过就按新音源重搜一次：只换标签不重搜，
                                // 用户会以为这个音源也搜不到同一首歌。
                                if (searchState.keyword.trim().isNotEmpty &&
                                    searchState.searched) {
                                  notifier.search(searchState.keyword.trim());
                                }
                              },
                            ),
                      ),
                    ],
                  ),
                ),
                if (overlayVisible)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                      child: _SearchResults(
                        state: searchState,
                        scrollController: _scrollController,
                        onTapSong: (song) {
                          queue.replaceQueue(searchState.results, song);
                          player.playSong(
                            song,
                            quality: settings.playbackQuality,
                          );
                          _focusNode.unfocus();
                          openNowPlaying(context);
                        },
                        currentId: playerState.currentSong?.id,
                        currentSource: playerState.currentSong?.source,
                        isPlaying: playerState.isPlaying,
                        onTogglePlay: () {
                          if (playerState.isPlaying) {
                            player.toggle();
                          } else if (playerState.currentSong != null) {
                            player.toggle();
                          }
                        },
                        onRetry: () => notifier.search(searchState.keyword),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      backgroundColor: scheme.surface,
    );
  }

  // ── 首页内容 ─────────────────────────────────────────
  Widget _buildHomeContent(SearchStateNotifier notifier) {
    final musicHallState = ref.watch(homeMusicHallStateProvider);
    final searchHistory = ref.watch(searchStateProvider).history;
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      color: scheme.primary,
      onRefresh:
          () => ref
              .read(homeMusicHallStateProvider.notifier)
              .load(
                source: ref.read(settingsStateProvider).searchSource,
                forceRefresh: true,
              ),
      // 光斑放在滚动内容之下（不随内容滚走）：它是「页面的气氛」，
      // 而不是某一段内容的一部分。放进 Sliver 里会被那一块的高度截成一条色带。
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AmbientGlow(
              height: MediaQuery.of(context).size.height * 0.5,
            ),
          ),
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              // 顶部留白：搜索框是浮在列表之上的，留的高度必须盖住
              // 「状态栏 + 搜索行」，否则问候语会被压在搜索框底下。
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.of(context).padding.top + 68,
                ),
              ),
              SliverToBoxAdapter(child: _Greeting()),
              if (searchHistory.isNotEmpty)
                SliverToBoxAdapter(
                  child: _HistoryChips(
                    history: searchHistory,
                    onTap: (h) {
                      _controller.text = h;
                      notifier.search(h);
                    },
                    onRemove: notifier.removeHistory,
                    onClear: notifier.clearHistory,
                  ),
                ),
              SliverToBoxAdapter(
                child: _RecentlyPlayed(
                  onTap: (song) {
                    final player = ref.read(playerControllerProvider.notifier);
                    player.playSong(
                      song,
                      quality: ref.read(settingsStateProvider).playbackQuality,
                    );
                    openNowPlaying(context);
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: '音乐馆',
                  subtitle: '各平台实时榜单',
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                  // 「全部」是导航入口，不依赖数据：原来按
                  // leaderboards.isEmpty 判定，加载期间它会消失再出现，
                  // 标题行的高度跟着抖一下。
                  trailing: _MoreButton(
                    onTap:
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder:
                                (_) => AllLeaderboardsScreen(
                                  source:
                                      musicHallState.loadedSource ??
                                      ref
                                          .read(settingsStateProvider)
                                          .searchSource,
                                ),
                          ),
                        ),
                  ),
                ),
              ),
              if (musicHallState.loading)
                const SliverToBoxAdapter(
                  child: SizedBox(
                    height: 220,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (musicHallState.leaderboards.isEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 220,
                    child: EmptyState(
                      icon: Icons.bar_chart_rounded,
                      title: '暂无榜单',
                      hint: musicHallState.error ?? '换个音源试试',
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          // 两列方格：封面是方形图，压扁成横条就只剩一条缝。
                          crossAxisCount: 2,
                          childAspectRatio: 0.86,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 14,
                        ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = musicHallState.leaderboards[index];
                        return LeaderboardCard(
                          // 按榜单 id 给 key：不加的话切换音源时
                          // Flutter 会按「第几个格子」复用同一个 Element，
                          // 卡片内部的封面缓存就这么留在原地，
                          // 出现「旧封面新文字」闪一下再换掉。
                          key: ValueKey('${item.source}:${item.id}'),
                          item: item,
                          source:
                              musicHallState.loadedSource ??
                              ref.read(settingsStateProvider).searchSource,
                        );
                      },
                      // 首页只铺前 12 个：网易云有 65 个榜，全铺出来要滚好几屏，
                      // 每张卡还要各补一次拼图，白白拖慢首屏。要全量看就进「全部」页。
                      childCount: musicHallState.leaderboards.length.clamp(
                        0,
                        12,
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 问候语 ───────────────────────────────────────────────
class _Greeting extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hour = DateTime.now().hour;
    final greeting =
        hour < 6
            ? '夜深了'
            : hour < 11
            ? '早上好'
            : hour < 14
            ? '中午好'
            : hour < 18
            ? '下午好'
            : '晚上好';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            greeting,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '今天想听点什么？',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ── 搜索框 ───────────────────────────────────────────────
class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final VoidCallback onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color:
            isDark
                ? SolaraColors.darkSurfaceHigh.withValues(alpha: 0.92)
                : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 13),
          Icon(Icons.search_rounded, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(fontSize: 14.5),
              cursorColor: scheme.primary,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索歌曲、歌手、专辑',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                border: InputBorder.none,
                isDense: true,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onSubmitted: onSubmitted,
              onChanged: (_) => onChanged(),
            ),
          ),
          if (loading)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: onClear,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  Icons.cancel_rounded,
                  size: 17,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}

// ── 「全部」入口 ─────────────────────────────────────────
//
// 首页音乐馆只铺前 12 张卡，剩下几十个榜要有个去处。
// 做成一颗带箭头的小胶囊而不是「查看更多」文字：标题右侧那点空间
// 放纯文字容易被当成说明而不是按钮。
class _MoreButton extends StatelessWidget {
  final VoidCallback onTap;
  const _MoreButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 6, 7, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '全部',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(width: 1),
              Icon(
                Icons.chevron_right_rounded,
                size: 17,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 搜索历史 chips ───────────────────────────────────────
class _HistoryChips extends StatelessWidget {
  final List<String> history;
  final ValueChanged<String> onTap;
  final ValueChanged<String> onRemove;
  final VoidCallback onClear;

  const _HistoryChips({
    required this.history,
    required this.onTap,
    required this.onRemove,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '最近搜索',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                history.map((h) {
                  return GestureDetector(
                    onTap: () => onTap(h),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 7, 7, 7),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            h,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.onSurface.withValues(alpha: 0.86),
                            ),
                          ),
                          const SizedBox(width: 5),
                          // 删除历史词以前只能长按，手势没提示等于没有。
                          // 给一颗小「×」，点一下就能删。
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onRemove(h),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                Icons.close_rounded,
                                size: 13,
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: 0.8,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── 搜索结果浮层 ─────────────────────────────────────────
class _SearchResults extends StatelessWidget {
  final SearchState state;
  final ScrollController scrollController;
  final ValueChanged<Song> onTapSong;
  final String? currentId;
  final String? currentSource;
  final bool isPlaying;
  final VoidCallback onTogglePlay;
  final VoidCallback onRetry;

  const _SearchResults({
    required this.state,
    required this.scrollController,
    required this.onTapSong,
    required this.currentId,
    required this.currentSource,
    required this.isPlaying,
    required this.onTogglePlay,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color:
              isDark
                  ? SolaraColors.darkSurfaceLow.withValues(alpha: 0.98)
                  : Colors.white,
          borderRadius: SolaraRadius.cardRadius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.12),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        state.error!,
                        style: TextStyle(color: scheme.error, fontSize: 12.5),
                      ),
                    ),
                    TextButton(onPressed: onRetry, child: const Text('重试')),
                  ],
                ),
              ),
            if (state.loading && state.results.isEmpty)
              const Flexible(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (state.results.isEmpty && state.error == null)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 26, 20, 30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 30,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '没有找到「${state.keyword}」',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '换个关键词，或换一个音源试试',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  controller: scrollController,
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: state.results.length + (state.hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= state.results.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    final song = state.results[index];
                    final isCurrent =
                        currentId == song.id && currentSource == song.source;
                    return SongRow(
                      song: song,
                      onTap: () => onTapSong(song),
                      trailing: IconButton(
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          isCurrent && isPlaying
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_fill_rounded,
                          color:
                              isCurrent
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                        ),
                        onPressed:
                            isCurrent ? onTogglePlay : () => onTapSong(song),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── 最近播放 ─────────────────────────────────────────────
class _RecentlyPlayed extends ConsumerWidget {
  final void Function(Song song) onTap;
  const _RecentlyPlayed({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyStateProvider).entries;
    if (history.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final playerState = ref.watch(playerControllerProvider);

    final seen = <String>{};
    final songs = <Song>[];
    for (final e in history) {
      final key = '${e.song.source}:${e.song.id}';
      if (seen.add(key)) songs.add(e.song);
      if (songs.length >= 6) break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '最近播放',
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
          // 首页只放 6 首，剩下的去历史页看。
          trailing: _MoreButton(
            onTap:
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children:
                    songs.map((song) {
                      final isCurrent =
                          song.id == playerState.currentSong?.id &&
                          song.source == playerState.currentSong?.source;
                      return GestureDetector(
                        onTap: () => onTap(song),
                        // 最近播放的方块是自绘的，不走 SongRow，
                        // 长按菜单要单独挂一次，否则这一块是唯一
                        // 「看到了歌但什么都做不了」的地方。
                        onLongPress: () => showSongActions(context, ref, song),
                        child: Container(
                          width: itemWidth,
                          height: 52,
                          decoration: BoxDecoration(
                            // 当前曲不再整块染色：深色底上 14% 的橙会糊成一片土褐，
                            // 反而比普通项更脏。改成中性底 + 一圈细描边，
                            // 标题单独上强调色，一眼就能定位「正在放的是这首」。
                            color: scheme.surfaceContainerHigh,
                            borderRadius: SolaraRadius.tileRadius,
                            border:
                                isCurrent
                                    ? Border.all(
                                      color: scheme.primary.withValues(
                                        alpha: 0.55,
                                      ),
                                    )
                                    : null,
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: const BorderRadius.horizontal(
                                  left: Radius.circular(SolaraRadius.tile),
                                ),
                                child: SongArtwork(
                                  picId: song.picId,
                                  source: song.source,
                                  picUrl: song.picUrl,
                                  size: 52,
                                  borderRadius: BorderRadius.zero,
                                ),
                              ),
                              const SizedBox(width: 10),
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
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color:
                                            isCurrent
                                                ? scheme.primary
                                                : scheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      song.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
              );
            },
          ),
        ),
      ],
    );
  }
}
