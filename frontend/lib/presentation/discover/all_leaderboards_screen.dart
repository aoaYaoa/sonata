import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../domain/models/discover.dart';
import '../../domain/state/settings_state.dart';
import '../widgets/leaderboard_card.dart';
import '../widgets/solara_ui.dart';

/// 全部榜单。
///
/// 首页音乐馆只铺前 12 张（首屏要快），这里把所选音源的榜单完整列出来。
///
/// 只列「有数据」的榜单：上游列表里混着详情页永远为空的榜（QQ 的 MV 榜、
/// B 站搜不到歌的几个分类、Jamendo 的部分 tag）。全铺出来就是一屏能点进去
/// 却全空的卡片。过滤在后端做（`available=1`），判定方式就是详情页取 1 首——
/// 与真正打开榜单走同一条路径，不会出现「列表说有、点进去没有」。
class AllLeaderboardsScreen extends ConsumerStatefulWidget {
  /// 音源。首页传当前音乐馆已加载的那个，保证「全部」列表和刚才看到的卡片同源；
  /// 不传则取设置里的当前音源。
  final String? source;

  const AllLeaderboardsScreen({super.key, this.source});

  @override
  ConsumerState<AllLeaderboardsScreen> createState() =>
      _AllLeaderboardsScreenState();
}

class _AllLeaderboardsScreenState extends ConsumerState<AllLeaderboardsScreen> {
  String _source = '';
  List<LeaderboardItem> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_source.isEmpty) {
      _source = widget.source ?? ref.read(settingsStateProvider).searchSource;
      _load();
    }
  }

  Future<void> _load() async {
    final source = _source;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(solaraRepositoryProvider);
      final items = await repo.fetchLeaderboardList(
        source: source,
        onlyAvailable: true,
      );
      if (!mounted || _source != source) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || _source != source) return;
      setState(() {
        _loading = false;
        _error = '加载失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AmbientGlow(
              height: MediaQuery.of(context).size.height * 0.42,
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TopBar(
                  source: _source,
                  onBack: () => Navigator.of(context).pop(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '全部榜单',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _subtitle(),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _body(scheme)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _subtitle() {
    if (_loading) return '正在筛选有内容的榜单…';
    if (_error != null) return '加载失败';
    return '${_items.length} 个有内容的榜单';
  }

  Widget _body(ColorScheme scheme) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(
              '正在逐个确认榜单内容',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: '加载失败',
        hint: _error,
        action: FilledButton(onPressed: _load, child: const Text('重试')),
      );
    }
    if (_items.isEmpty) {
      return const EmptyState(
        icon: Icons.bar_chart_rounded,
        title: '这个音源暂时没有可用的榜单',
        hint: '换一个音源试试',
      );
    }
    return RefreshIndicator(
      color: scheme.primary,
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 28),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.86,
          crossAxisSpacing: 12,
          mainAxisSpacing: 14,
        ),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          return LeaderboardCard(
            key: ValueKey('${item.source}:${item.id}'),
            item: item,
            source: _source,
          );
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String source;
  final VoidCallback onBack;
  const _TopBar({required this.source, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
            onPressed: onBack,
          ),
          const Spacer(),
          if (source.isNotEmpty)
            MiniTag(
              text: leaderboardSourceBadge(source),
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
              textColor: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }
}
