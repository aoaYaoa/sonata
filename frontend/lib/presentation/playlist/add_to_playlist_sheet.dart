import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/models/song.dart';
import '../../domain/state/playlist_state.dart';
import 'playlist_screen.dart' show showCreatePlaylistDialog;

/// 「添加到歌单」弹层。
///
/// 这个弹层原来定义在 `playlist_screen.dart` 里却没有任何调用点——歌单空态
/// 写着「在搜索结果里长按或点『更多』加入歌曲」，但两处都没有这个入口。
/// 挪到这里之后由歌曲长按菜单调用，那句提示才算兑现。
class AddToPlaylistSheet extends ConsumerWidget {
  final Song song;
  const AddToPlaylistSheet({super.key, required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(playlistStateProvider);
    final notifier = ref.read(playlistStateProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Text(
                '添加到歌单',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 10),
              child: Text(
                song.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (state.playlists.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: TextButton.icon(
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('新建歌单'),
                    onPressed: () => showCreatePlaylistDialog(context, ref),
                  ),
                ),
              )
            else
              // 歌单可能有几十个，加个高度上限自己滚，否则长列表会把弹层
              // 顶到屏幕外、底部的「新建」再也够不着。
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ...state.playlists.map(
                      (p) => Material(
                        color: Colors.transparent,
                        borderRadius: SolaraRadius.tileRadius,
                        child: InkWell(
                          borderRadius: SolaraRadius.tileRadius,
                          onTap: () {
                            notifier.addSongToPlaylist(p.id, song);
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('已添加到「${p.name}」')),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 13,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.queue_music_rounded,
                                  size: 19,
                                  color: scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                                Text(
                                  '${p.songs.length}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('新建歌单'),
                      onPressed: () => showCreatePlaylistDialog(context, ref),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> showAddToPlaylistSheet(
  BuildContext context, {
  required Song song,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => AddToPlaylistSheet(song: song),
  );
}
