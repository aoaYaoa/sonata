import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'cover_image.dart';

/// 歌曲封面（自动补全 picId → URL）。
///
/// 搜索结果、收藏、历史里的 Song 大多只有 picId，没有直链，
/// 需要一个异步请求才能拿到封面；这里带进程内缓存，避免来回滚动反复请求。
/// 直链（picUrl）存在时直接渲染，不发请求。
class SongArtwork extends ConsumerStatefulWidget {
  final String picId;
  final String source;
  final String? picUrl;
  final double size;
  final double? width;
  final BorderRadius? borderRadius;
  final double iconSize;

  const SongArtwork({
    super.key,
    required this.picId,
    required this.source,
    this.picUrl,
    this.size = 48,
    this.width,
    this.borderRadius,
    this.iconSize = 20,
  });

  @override
  ConsumerState<SongArtwork> createState() => _SongArtworkState();
}

class _SongArtworkState extends ConsumerState<SongArtwork> {
  static final Map<String, String> _cache = {};
  Future<String?>? _future;

  String get _key => '${widget.source}:${widget.picId}';

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant SongArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.picId != widget.picId || oldWidget.source != widget.source) {
      _future = null;
      _resolve();
    }
  }

  void _resolve() {
    if ((widget.picUrl ?? '').isNotEmpty) return;
    if (widget.picId.isEmpty) return;
    if (_cache.containsKey(_key)) return;
    _future = ref
        .read(solaraRepositoryProvider)
        .fetchPicUrl(picId: widget.picId, source: widget.source, size: 120)
        .then((url) {
          _cache[_key] = url;
          return url;
        })
        .catchError((_) => '');
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width ?? widget.size;
    final radius = widget.borderRadius;

    Widget image(String url) => CoverImage(
      url: url,
      width: w,
      height: widget.size,
      borderRadius: radius,
      fallbackIconSize: widget.iconSize,
    );

    final direct = widget.picUrl ?? '';
    if (direct.isNotEmpty) return image(direct);

    final cached = _cache[_key];
    if (cached != null && cached.isNotEmpty) return image(cached);

    if (_future == null) {
      return CoverImage(
        url: '',
        width: w,
        height: widget.size,
        borderRadius: radius,
        fallbackIconSize: widget.iconSize,
      );
    }

    return FutureBuilder<String?>(
      future: _future,
      builder: (_, snap) {
        final url = snap.data ?? '';
        return CoverImage(
          url: url,
          width: w,
          height: widget.size,
          borderRadius: radius,
          fallbackIconSize: widget.iconSize,
        );
      },
    );
  }
}
