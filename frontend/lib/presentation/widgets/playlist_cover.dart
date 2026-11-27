import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'cover_collage.dart';
import 'cover_image.dart';

/// 歌单 / 榜单卡片的封面。
///
/// 为什么不能直接铺平台给的封面：国内平台的榜单和歌单封面大多是「品牌设计图」——
/// 纯色底上印着一行大字（网易云飙升榜紫底白字、QQ 飙升榜红底白字、各种歌单的
/// 海报式封面）。铺到卡片上，用户看到的还是一行字，等于没换。
///
/// 所以优先铺「前 4 首歌的专辑封面拼图」。这里处理三种状态：
///  1. 已经有拼图（后端随列表一起给了）→ 直接铺；
///  2. 还没拿到 → **先铺渐变占位，绝不在这个中间态里铺品牌图**。
///     这是关键：先铺品牌文字图、几秒后再换成拼图，用户看到的正是
///     「旧的文字卡片闪一下再刷新」，这正是要消掉的现象；
///  3. 确认拿不到（重试两次仍失败）→ 才退回品牌图。
class PlaylistCover extends ConsumerStatefulWidget {
  final String id;
  final String source;

  /// 列表接口随回来就带的拼图，命中时连请求都不用发。
  final List<String> initialUrls;

  /// 平台自带封面，只在拼图确认失败时兜底。
  final String brandUrl;

  final IconData fallbackIcon;

  const PlaylistCover({
    super.key,
    required this.id,
    required this.source,
    this.initialUrls = const [],
    this.brandUrl = '',
    this.fallbackIcon = Icons.queue_music_rounded,
  });

  @override
  ConsumerState<PlaylistCover> createState() => _PlaylistCoverState();
}

class _PlaylistCoverState extends ConsumerState<PlaylistCover> {
  late List<String> _tiles;
  bool _requested = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _tiles = widget.initialUrls;
    if (_tiles.isEmpty) _fetch();
  }

  @override
  void didUpdateWidget(PlaylistCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 网格按位置复用 Element：换音源 / 换分类后同一格会换成另一个歌单。
    // 不重置的话 _tiles 还停在上一个的封面，出现「旧图配新名」。
    if (oldWidget.id != widget.id || oldWidget.source != widget.source) {
      _tiles = widget.initialUrls;
      _requested = false;
      _failed = false;
      if (_tiles.isEmpty) _fetch();
    }
  }

  Future<void> _fetch() async {
    if (_requested) return;
    _requested = true;
    // 上游偶尔对某个榜返回空（冷门榜很常见），补一次就能拿到。
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final urls = await ref
            .read(solaraRepositoryProvider)
            .fetchLeaderboardCovers(id: widget.id, source: widget.source);
        if (!mounted) return;
        if (urls.isNotEmpty) {
          setState(() => _tiles = urls);
          return;
        }
      } catch (_) {
        // 单次失败继续重试
      }
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    }
    if (!mounted) return;
    setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_tiles.isNotEmpty) {
      return CoverCollage(
        // id 变了要整块重建，避免拼图子项按位置复用旧图。
        key: ValueKey('collage:${widget.id}'),
        urls: _tiles,
      );
    }
    if (_failed && widget.brandUrl.isNotEmpty) {
      return CoverImage(
        url: widget.brandUrl,
        borderRadius: BorderRadius.zero,
        fallbackIcon: widget.fallbackIcon,
      );
    }
    // 等待拼图期间：中性占位。这里刻意不铺品牌图，
    // 否则就会出现「文字卡片先闪一下再刷成图」。
    return _PendingCover(seed: widget.id, icon: widget.fallbackIcon);
  }
}

/// 拼图加载中的占位：不写字、不铺品牌图，只有一层极淡的渐变和图标。
class _PendingCover extends StatelessWidget {
  final String seed;
  final IconData icon;

  const _PendingCover({required this.seed, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hash = seed.codeUnits.fold(0, (a, b) => a * 31 + b);
    final hue = (hash.abs() % 360).toDouble();
    final base =
        HSLColor.fromAHSL(
          1,
          hue,
          isDark ? 0.28 : 0.20,
          isDark ? 0.18 : 0.90,
        ).toColor();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base,
            Color.alphaBlend(scheme.surface.withValues(alpha: 0.5), base),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          icon,
          size: 26,
          color:
              isDark
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: 0.10),
        ),
      ),
    );
  }
}
