import 'package:flutter/material.dart';

import '../../services/image_headers.dart' show sizedCoverUrl;

/// 2x2 专辑封面拼图。
///
/// 为什么需要它：国内音乐平台的「榜单/歌单封面」大多是品牌设计图——纯色底上
/// 印着榜名文字（网易云飙升榜是紫底白字、酷狗 TOP500 是红底白字）。直接铺到
/// 卡片上，用户看到的仍然是一行字，跟改造前没有区别。拼 4 张真实专辑封面
/// 才是「像图片」的效果，也是 QQ 音乐 / Apple Music 的通行做法。
///
/// 不足 4 张时循环补齐；一张都没有时由调用方回退到渐变占位。
class CoverCollage extends StatelessWidget {
  final List<String> urls;

  const CoverCollage({super.key, required this.urls});

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final tiles = List<String>.generate(4, (i) => urls[i % urls.length]);
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 1.5,
        mainAxisSpacing: 1.5,
      ),
      itemCount: 4,
      itemBuilder:
          (context, i) => ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: Image.network(
              // 拼图的 4 个位置是固定的，换榜单时只有 url 变。
              // key 带上 url 才能强制重建 State；否则 gaplessPlayback 会把
              // 上一张拼图留在屏幕上，看起来像「没刷新」。
              key: ValueKey(tiles[i]),
              sizedCoverUrl(tiles[i], size: 300),
              fit: BoxFit.cover,
              cacheWidth: 300,
              // 解码完成前露出底色、完成后淡入：不做这一步，换榜单时四个格子
              // 会先白一下再「啪」地出现，比留旧图更刺眼。
              frameBuilder: (context, child, frame, wasSync) {
                if (wasSync) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: child,
                );
              },
              errorBuilder:
                  (_, __, ___) =>
                      Icon(Icons.music_note, size: 20, color: Colors.white24),
            ),
          ),
    );
  }
}
