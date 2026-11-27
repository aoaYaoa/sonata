import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/state/local_songs_state.dart';
import '../../domain/state/queue_state.dart';
import '../../domain/state/settings_state.dart';
import '../../services/local_music_service.dart';
import '../../services/player_controller.dart';
import '../now_playing/open_now_playing.dart';

/// 导入本地音乐。
///
/// 这段逻辑原来只挂在「我的 → 本地」长按上——一个没有任何提示的隐藏手势，
/// 用户几乎不可能发现。现在同时挂在明面上的「导入」按钮（本地面板头部与空状态），
/// 长按保留当快捷方式。
///
/// [playFirst] 为 true 时导入完直接播第一首（「我的」页长按进来的老行为）；
/// 在面板里点「导入」则不动当前播放。
Future<void> importLocalMusic(
  BuildContext context,
  WidgetRef ref, {
  bool playFirst = false,
}) async {
  final songs = await LocalMusicService.pickFiles();
  if (songs.isEmpty) return;
  await ref.read(localSongsProvider.notifier).addSongs(songs);
  if (!context.mounted) return;

  final allLocal = ref.read(localSongsProvider);

  if (playFirst) {
    final picked = allLocal.firstWhere(
      (s) => s.id == songs.first.id,
      orElse: () => songs.first,
    );
    ref.read(queueStateProvider.notifier).replaceQueue(allLocal, picked);
    ref
        .read(playerControllerProvider.notifier)
        .playSong(
          picked,
          quality: ref.read(settingsStateProvider).playbackQuality,
        );
    if (!context.mounted) return;
    openNowPlaying(context);
  }

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('已导入 ${songs.length} 首，共 ${allLocal.length} 首本地歌曲')),
  );
}
