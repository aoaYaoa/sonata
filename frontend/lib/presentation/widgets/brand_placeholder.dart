import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// 品牌占位图：没有封面时用 SONATA 的图形顶上。
///
/// 以前这里是一块「主色 + 白色音符」的纯色，和任何一首歌都无关——
/// 播放页唱片、列表缩略图、播放条都这样，看起来像「加载失败」而不是
/// 「这首歌本来就没封面」。换成品牌图形后，至少是设计过的空态。
///
/// 用 `assets/app_icon.png`：它和 App 图标同一张图，只是不带系统那条圆角裁切，
/// 铺进播放页的圆形唱片里正好满幅。
class BrandPlaceholder extends StatelessWidget {
  /// 未指定尺寸时铺满父容器（`Image.asset` 的 `fit: cover` 自己会裁）。
  final double? size;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final double opacity;

  const BrandPlaceholder({
    super.key,
    this.size,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.opacity = 1,
  });

  @override
  Widget build(BuildContext context) {
    Widget image = Image.asset(
      'assets/app_icon.png',
      width: size,
      height: size,
      fit: fit,
      filterQuality: FilterQuality.medium,
      opacity: AlwaysStoppedAnimation<double>(opacity),
      // 占位图本身就是「没有内容」的信号，不需要再叠一层图标。
      errorBuilder:
          (context, _, __) => _Fallback(
            size: size,
            color: Theme.of(context).colorScheme.primary,
          ),
    );
    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }
}

/// asset 缺失时的最后兜底（理论上不会走到，避免白屏）。
class _Fallback extends StatelessWidget {
  final double? size;
  final Color color;
  const _Fallback({this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: SolaraColors.sunset,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        size: (size ?? 48) * 0.4,
        color: Colors.white.withValues(alpha: 0.85),
      ),
    );
  }
}
