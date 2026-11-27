import 'package:flutter/material.dart';

import '../../services/image_headers.dart' show sizedCoverUrl;
import '../../app/theme.dart';

/// 统一的封面图组件。
///
/// 直接用 `Image.network` 的观感问题有三个：图片解码完会「啪」地跳出来、
/// 失败时留一块黑、圆角要每处自己 Clip。这里一次性解决：
///  - 淡入过渡，占位色和卡片底色一致，不闪黑；
///  - 失败退化成带音符的色块，不留空洞；
///  - 按显示尺寸请求 CDN 小图（cacheWidth），滚动更顺。
class CoverImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final BoxFit fit;

  /// 请求给 CDN 的边长倍率。Retina 下按 2x 取图足够清晰。
  final int pixelRatio;
  final Color? background;
  final IconData fallbackIcon;
  final double fallbackIconSize;

  const CoverImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.borderRadius,
    this.fit = BoxFit.cover,
    this.pixelRatio = 2,
    this.background,
    this.fallbackIcon = Icons.music_note_rounded,
    this.fallbackIconSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = background ?? scheme.surfaceContainerHigh;
    final radius = borderRadius ?? SolaraRadius.thumbRadius;
    final logical = (width ?? height ?? 0) * pixelRatio;

    Widget fallback() => Container(
      width: width,
      height: height,
      color: bg,
      alignment: Alignment.center,
      child: Icon(
        fallbackIcon,
        size: fallbackIconSize,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );

    if (url.isEmpty) {
      return ClipRRect(borderRadius: radius, child: fallback());
    }

    return ClipRRect(
      borderRadius: radius,
      child: ColoredBox(
        color: bg,
        child: Image.network(
          // key 带上 url：同一位置换了封面时强制重建 State，
          // 否则 gaplessPlayback 会把上一张图留在屏幕上，看起来像没刷新。
          key: ValueKey(url),
          sizedCoverUrl(url, size: logical > 0 ? logical.toInt() : 400),
          width: width,
          height: height,
          fit: fit,
          gaplessPlayback: true,
          cacheWidth: logical > 0 ? logical.toInt() : null,
          frameBuilder: (context, child, frame, wasSync) {
            if (wasSync) return child;
            // 解码完成前先留一块底色，完成后淡入：避免图片「啪」地跳出来。
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: child,
            );
          },
          errorBuilder: (_, __, ___) => fallback(),
        ),
      ),
    );
  }
}
