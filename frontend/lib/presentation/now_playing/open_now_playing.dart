import 'package:flutter/material.dart';

import 'now_playing_screen.dart';

/// 打开「正在播放」页。
///
/// 全屏淡入而不是标准 push 的右侧滑入：播放页是从底部播放条「长上来」的，
/// 横向滑动会让人觉得「翻了一页」，纵向展开才对得上这个心智。
///
/// 这个入口原来在播放条、macOS 侧栏各写了一份 PageRouteBuilder，
/// 现在点歌也要跳过去，再复制一份就该出现三种转场时长了。
Future<void> openNowPlaying(BuildContext context) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      pageBuilder:
          (_, animation, __) => FadeTransition(
            opacity: animation,
            child: const NowPlayingScreen(),
          ),
      fullscreenDialog: true,
      transitionDuration: const Duration(milliseconds: 380),
    ),
  );
}
