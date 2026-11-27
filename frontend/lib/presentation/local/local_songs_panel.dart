import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/state/local_songs_state.dart';
import '../../domain/state/queue_state.dart';
import '../../domain/state/settings_state.dart';
import '../../services/player_controller.dart';
import '../now_playing/open_now_playing.dart';
import '../widgets/solara_ui.dart';
import '../widgets/song_row.dart';
import 'import_local_music.dart';

class LocalSongsPanel extends ConsumerWidget {
  const LocalSongsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final songs = ref.watch(localSongsProvider);

    if (songs.isEmpty) {
      // 空态里放一枚「导入」按钮：原来这里只写「在『我的音乐』页长按本地」，
      // 而长按是个没有提示的手势，等于把功能藏起来了。
      return EmptyState(
        icon: Icons.folder_open_rounded,
        title: '还没有本地歌曲',
        hint: '支持 mp3 / flac / m4a / wav 等格式',
        action: FilledButton.icon(
          icon: const Icon(Icons.file_open_rounded, size: 18),
          label: const Text('导入音频文件'),
          onPressed: () => importLocalMusic(context, ref),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
          child: Row(
            children: [
              Text(
                '${songs.length} 首',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('导入'),
                onPressed: () => importLocalMusic(context, ref),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('全部播放'),
                onPressed: () {
                  final queue = ref.read(queueStateProvider.notifier);
                  final player = ref.read(playerControllerProvider.notifier);
                  final settings = ref.read(settingsStateProvider);
                  queue.replaceQueue(songs, songs.first);
                  player.playSong(
                    songs.first,
                    quality: settings.playbackQuality,
                  );
                  openNowPlaying(context);
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 20),
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              final notifier = ref.read(localSongsProvider.notifier);
              return SongRow(
                song: song,
                showArtwork: false,
                onTap: () {
                  final queue = ref.read(queueStateProvider.notifier);
                  final player = ref.read(playerControllerProvider.notifier);
                  final settings = ref.read(settingsStateProvider);
                  queue.replaceQueue(songs, song);
                  player.playSong(song, quality: settings.playbackQuality);
                  openNowPlaying(context);
                },
                onLongPress:
                    () => showLocalSongMenu(context, ref, song.id, () {
                      notifier.removeSong(song.id);
                    }),
                trailing: IconButton(
                  iconSize: 19,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                  onPressed: () => notifier.removeSong(song.id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 本地歌曲没有网络侧的动作（不能加入歌单除了搜索那套 id 也不通用），
/// 所以这里的小菜单只留一个删除。
void showLocalSongMenu(
  BuildContext context,
  WidgetRef ref,
  String songId,
  VoidCallback onRemove,
) {
  showModalBottomSheet<void>(
    context: context,
    builder:
        (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: Theme.of(ctx).colorScheme.error,
                  ),
                  title: Text(
                    '从本地移除',
                    style: TextStyle(
                      color: Theme.of(ctx).colorScheme.error,
                      fontSize: 14,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    onRemove();
                  },
                ),
              ],
            ),
          ),
        ),
  );
}
