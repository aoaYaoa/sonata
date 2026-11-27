import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/song.dart';
import '../../domain/state/favorites_state.dart';
import '../../domain/state/queue_state.dart';
import '../../domain/state/settings_state.dart';
import '../../services/player_controller.dart';
import '../now_playing/open_now_playing.dart';
import '../widgets/solara_ui.dart';
import '../widgets/song_row.dart';

class FavoritesPanel extends ConsumerWidget {
  const FavoritesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final songs = ref.watch(favoritesStateProvider).favorites;
    final favorites = ref.read(favoritesStateProvider.notifier);
    final player = ref.read(playerControllerProvider.notifier);
    final queue = ref.read(queueStateProvider.notifier);
    final settings = ref.read(settingsStateProvider);

    if (songs.isEmpty) {
      return const EmptyState(
        icon: Icons.favorite_border_rounded,
        title: '还没有收藏',
        hint: '在歌曲上点一下心形按钮',
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
          child: Row(
            children: [
              Text(
                '共 ${songs.length} 首',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('全部播放'),
                onPressed: () {
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
              final Song song = songs[index];
              return SongRow(
                song: song,
                onTap: () {
                  queue.replaceQueue(songs, song);
                  player.playSong(song, quality: settings.playbackQuality);
                  openNowPlaying(context);
                },
                trailing: IconButton(
                  iconSize: 19,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.favorite_rounded, color: scheme.primary),
                  onPressed: () => favorites.toggleFavorite(song),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
