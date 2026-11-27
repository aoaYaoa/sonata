import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/models/discover.dart';
import '../discover/leaderboard_detail_screen.dart';
import 'playlist_cover.dart';
import 'solara_ui.dart';

/// 音源短名（榜单卡片左上角的小标签用）。
String leaderboardSourceBadge(String s) {
  switch (s) {
    case 'netease':
      return '网易云';
    case 'tencent':
      return 'QQ';
    case 'kugou':
      return '酷狗';
    case 'bilibili':
      return 'B站';
    case 'youtube':
      return 'YouTube';
    case 'jamendo':
      return 'Jamendo';
    default:
      return s;
  }
}

/// 榜单卡片：封面 + 压在封面上的榜名。
///
/// 设计要点：卡片要像一张图，不能像一条文字。
///  - 有 coverUrls（榜单前几首歌的专辑图）时铺 2x2 拼图，这是主要形态；
///  - 没有时退回榜单自带封面（品牌图，仍是一张图）；
///  - 都没有才退化成渐变底色块。
///
/// 首页音乐馆和「全部榜单」页共用这一个组件，避免两处样式漂移。
class LeaderboardCard extends ConsumerStatefulWidget {
  final LeaderboardItem item;
  final String source;

  /// 卡片要铺满的高度由外部决定（首页用 grid 的 Expanded，列表页给固定宽高）。
  const LeaderboardCard({super.key, required this.item, required this.source});

  @override
  ConsumerState<LeaderboardCard> createState() => _LeaderboardCardState();
}

class _LeaderboardCardState extends ConsumerState<LeaderboardCard> {
  @override
  Widget build(BuildContext context) {
    final brand = widget.item.coverUrl ?? '';
    final meta = (widget.item.updateFrequency ?? '').trim();
    final item = widget.item;
    final source = widget.source;

    return GestureDetector(
      onTap:
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => LeaderboardDetailScreen(item: item, source: source),
            ),
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: SolaraRadius.cardRadius,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 统一走 PlaylistCover：有拼图铺拼图，没有就先铺中性占位再补图，
                  // 只有在「确认拿不到」时才退回平台品牌图。
                  // 不在中间态铺品牌图，正是为了消掉「文字卡片先闪一下再刷新」。
                  PlaylistCover(
                    id: item.id,
                    source: item.source,
                    initialUrls: item.coverUrls,
                    brandUrl: brand,
                    fallbackIcon: Icons.bar_chart_rounded,
                  ),
                  // 从左下起一层柔和暗角：白字压在任何封面上都清楚
                  const ScrimOverlay(start: 0.46),
                  Positioned(
                    left: 9,
                    top: 9,
                    child: MiniTag(text: sourceBadge(source)),
                  ),
                  Positioned(
                    left: 11,
                    right: 11,
                    bottom: 11,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 10,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String sourceBadge(String s) => leaderboardSourceBadge(s);
}
