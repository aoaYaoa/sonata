import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/providers.dart';
import '../../domain/models/discover.dart';
import '../../domain/models/music_source.dart';
import '../../domain/state/settings_state.dart';
import '../../services/app_config.dart';
import '../../services/debug_log_bus.dart';
import '../widgets/playlist_cover.dart';
import '../widgets/solara_ui.dart';
import '../widgets/source_picker.dart';
import 'song_list_detail_screen.dart';

/// 发现页：所选音源的推荐歌单瀑布流。
///
/// 版式：顶部一个大标题 + 音源胶囊，往下是三列方形封面网格（手机竖屏）。
/// 卡片形态对齐网易云/QQ 音乐的「封面 + 下方两行字」，而不是把文字压在图的
/// 下半部分——压字会让封面主体被遮掉一半，看起来更像宣传图而不是曲库。
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _scrollController = ScrollController();
  String _currentSource = '';
  List<SongListItem> _songLists = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;
  String? _loadMoreError;

  /// 曲风筛选，空串表示「全部」。
  ///
  /// 后端 `/api/discover/songlist` 早就支持 `tag` 参数（走网易云的
  /// `playlist/list?cat=`），前端一直没接——`AppConfig.genres` 里的
  /// 13 个曲风全项目零引用。只有网易云有这个分类维度，其它音源不显示。
  String _tag = '';

  bool get _supportsGenre => _currentSource == 'netease';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final source = ref.read(settingsStateProvider).discoverSource;
    if (source != _currentSource) {
      _loadSource(source);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 请求序号：切音源/切曲风时，晚回来的旧请求直接丢弃。
  ///
  /// 否则连点两个曲风时，前一个的响应会覆盖后一个的结果——
  /// 标题写着「摇滚」，列表却是「流行」的数据。
  int _requestId = 0;

  Future<void> _loadSource(String source) async {
    if (!mounted) return;
    final requestId = ++_requestId;
    setState(() {
      // 换到没有曲风维度的音源时把筛选清掉：否则标题还挂着上一个音源
      // 的中文曲风（「电子 · 酷狗推荐」），而那其实是无效条件。
      if (source != 'netease') _tag = '';
      _currentSource = source;
      _songLists = [];
      _page = 1;
      _hasMore = true;
      _error = null;
      _loading = true;
      _loadingMore = false;
    });
    try {
      final repo = ref.read(solaraRepositoryProvider);
      final items = await repo.fetchSongList(
        source: source,
        tag: _tag,
        page: 1,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _songLists = items;
        _loading = false;
        _hasMore = items.length >= 30;
        _loadMoreError = null;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _error = '加载失败: $e';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    final source = _currentSource;
    setState(() => _loadingMore = true);
    try {
      final repo = ref.read(solaraRepositoryProvider);
      final nextPage = _page + 1;
      final items = await repo.fetchSongList(
        source: source,
        tag: _tag,
        page: nextPage,
      );
      if (!mounted || _currentSource != source) return;
      setState(() {
        _songLists = [..._songLists, ...items];
        _page = nextPage;
        _loadingMore = false;
        _hasMore = items.length >= 30;
      });
    } catch (e) {
      if (!mounted) return;
      // 原来这里是 catch (_) 静默吞掉：滚到底没反应也没提示，
      // 用户只能反复往下拉。现在记下错误，底部那颗「加载失败，点击重试」能点。
      setState(() {
        _loadingMore = false;
        _loadMoreError = '加载更多失败';
      });
      DebugLogBus.add('[Discover] loadMore 失败: $e');
    }
  }

  Future<void> _retryLoadMore() async {
    setState(() => _loadMoreError = null);
    await _loadMore();
  }

  Future<void> _selectTag(String tag) async {
    if (tag == _tag) return;
    setState(() => _tag = tag);
    await _loadSource(_currentSource);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  String _sourceLabel(String source) => MusicSource.shortLabel(source);

  @override
  Widget build(BuildContext context) {
    ref.listen<SettingsState>(settingsStateProvider, (prev, next) {
      if (prev?.discoverSource != next.discoverSource) {
        _loadSource(next.discoverSource);
      }
    });

    final settings = ref.watch(settingsStateProvider);
    final scheme = Theme.of(context).colorScheme;
    final source = settings.discoverSource;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: RefreshIndicator(
        color: scheme.primary,
        onRefresh: () => _loadSource(source),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverAppBar(
              pinned: true,
              toolbarHeight: 64,
              backgroundColor: scheme.surface,
              surfaceTintColor: Colors.transparent,
              title: const Text('发现'),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: SourcePill(
                    label: _sourceLabel(source),
                    onTap:
                        () => showSourceSheet(
                          context,
                          current: source,
                          onSelected:
                              (value) => ref
                                  .read(settingsStateProvider.notifier)
                                  .setDiscoverSource(value),
                        ),
                  ),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  _tag.isEmpty
                      ? '${_sourceLabel(source)}的推荐歌单'
                      : '$_tag · ${_sourceLabel(source)}推荐',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ),
            if (_supportsGenre)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final tag in ['全部', ...AppConfig.genres])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _GenreChip(
                            label: tag,
                            selected: tag == '全部' ? _tag.isEmpty : tag == _tag,
                            // 「全部」用空串表示：后端 tag 为空时走 cat=全部，
                            // 传「全部」两个字反而不对。
                            onTap: () => _selectTag(tag == '全部' ? '' : tag),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 14)),
            if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: scheme.error, fontSize: 12.5),
                        ),
                      ),
                      // 失败时给一个明确的「重试」：原来只有一行红字，
                      // 想再试一次只能下拉刷新，而错误状态下没人会想到下拉。
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('重试'),
                        onPressed: () => _loadSource(source),
                      ),
                    ],
                  ),
                ),
              ),
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_songLists.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.queue_music_rounded,
                  title: '这个音源暂时没有歌单',
                  hint: '右上角换个音源试试',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.68,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 16,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _SongListCard(
                      // 同上：换曲风/音源时按歌单 id 定位，不复用旧格子。
                      key: ValueKey(_songLists[index].id),
                      item: _songLists[index],
                      source: source,
                      index: index,
                    ),
                    childCount: _songLists.length,
                  ),
                ),
              ),
            if (_loadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              )
            else if (_loadMoreError != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  child: Center(
                    child: TextButton.icon(
                      onPressed: _retryLoadMore,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: Text('$_loadMoreError，点击重试'),
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

/// 歌单卡：方形封面 + 下方两行文字。
class _SongListCard extends StatelessWidget {
  final SongListItem item;
  final String source;
  final int index;
  const _SongListCard({
    super.key,
    required this.item,
    required this.source,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cover = item.coverUrl ?? '';

    return GestureDetector(
      onTap:
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SongListDetailScreen(item: item, source: source),
            ),
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: SolaraRadius.tileRadius,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 网易云的歌单封面是「海报式设计图」，上面写着歌单名。
                  // 直接铺上去用户看到的还是一行字，所以同样先补专辑拼图。
                  PlaylistCover(id: item.id, source: source, brandUrl: cover),
                  // 播放量角标
                  if ((item.playCount ?? '').isNotEmpty)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: MiniTag(
                        text: _formatCount(item.playCount!),
                        icon: Icons.play_arrow_rounded,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.3,
              fontWeight: FontWeight.w500,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatCount(String raw) {
    final n = int.tryParse(raw);
    if (n == null) return raw;
    if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return '$n';
  }
}

/// 曲风胶囊。和音源胶囊的区别：这是「多选一」的筛选态，
/// 用填充色而不是下拉箭头，选中时一眼能认出来。
class _GenreChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GenreChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color:
              selected
                  ? scheme.primary.withValues(alpha: 0.16)
                  : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                selected
                    ? scheme.primary.withValues(alpha: 0.5)
                    : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.primary : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}
