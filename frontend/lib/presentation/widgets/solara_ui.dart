import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// 分区标题：大字号标题 + 可选的「更多」入口。
///
/// 参考网易云/QQ 音乐的首页：标题是页面的骨架，
/// 用 17~18pt 粗体 + 一块颜色引导视线，比一行 14pt 小字更像成品。
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 22, 16, 12),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: scheme.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 卡片底部的黑色渐变，保证白字压在任何图片上都清晰。
class ScrimOverlay extends StatelessWidget {
  final double start;
  final Color color;

  const ScrimOverlay({
    super.key,
    this.start = 0.35,
    this.color = const Color(0xE6000000),
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [start, 1.0],
          colors: [Colors.transparent, color],
        ),
      ),
    );
  }
}

/// 毛玻璃底板：导航栏、播放条、浮层共用的质感。
///
/// 只有模糊 + 半透明才叫「浮在内容上」；纯色条会显得像切了一刀。
class GlassSurface extends StatelessWidget {
  final Widget child;
  final double blur;
  final Color? color;
  final BorderRadius? borderRadius;
  final Border? border;

  const GlassSurface({
    super.key,
    required this.child,
    this.blur = 24,
    this.color,
    this.borderRadius,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg =
        color ??
        (isDark
            ? SolaraColors.darkSurface.withValues(alpha: 0.72)
            : Colors.white.withValues(alpha: 0.78));
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: borderRadius,
            border: border,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 小圆角标签（音源、音质、试听等）。
class MiniTag extends StatelessWidget {
  final String text;
  final Color? color;
  final Color? textColor;
  final IconData? icon;

  const MiniTag({
    super.key,
    required this.text,
    this.color,
    this.textColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color ?? Colors.black.withValues(alpha: 0.42);
    final fg = textColor ?? Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontSize: 9.5,
              height: 1.2,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶部的品牌渐变光斑，给白底/黑底页面一点气氛。
///
/// 用两团径向渐变叠在页面顶端，模拟「光从封面透上来」，
/// 是 Spotify/Apple Music 首页最常见的做法。
class AmbientGlow extends StatelessWidget {
  final Color primary;
  final Color secondary;
  final double height;

  const AmbientGlow({
    super.key,
    this.primary = SolaraColors.brand,
    this.secondary = SolaraColors.brandAlt,
    this.height = 320,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final strength = isDark ? 0.30 : 0.16;
    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        // 光斑必须往下淡出，否则底部会留一条生硬的色带，
        // 看起来像「一块粉色背景板」而不是「光透上来」。
        child: ShaderMask(
          shaderCallback:
              (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.55, 1.0],
                colors: [Colors.white, Colors.white54, Colors.transparent],
              ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: Stack(
            children: [
              Positioned(
                left: -80,
                top: -140,
                child: _Blob(
                  color: primary.withValues(alpha: strength),
                  size: 300,
                ),
              ),
              Positioned(
                right: -100,
                top: -80,
                child: _Blob(
                  color: secondary.withValues(alpha: strength * 0.8),
                  size: 260,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;
  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}

/// 空状态：图标 + 一句话，统一各面板的空列表观感。
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint!,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}
