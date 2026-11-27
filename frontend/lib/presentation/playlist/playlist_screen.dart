import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/user_playlist.dart';
import '../../domain/state/playlist_state.dart';
import '../../domain/state/queue_state.dart';
import '../../domain/state/settings_state.dart';
import '../../services/player_controller.dart';
import '../now_playing/open_now_playing.dart';
import '../widgets/cover_collage.dart';
import '../widgets/cover_image.dart';
import '../widgets/solara_ui.dart';
import '../widgets/song_actions.dart';
import '../widgets/song_row.dart';

/// 新建/编辑歌单的对话框。我的音乐页与歌单页共用。
Future<void> showCreatePlaylistDialog(
  BuildContext context,
  WidgetRef ref, {
  UserPlaylist? editing,
}) {
  final nameController = TextEditingController(text: editing?.name);
  final descController = TextEditingController(text: editing?.description);
  return showDialog<void>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          title: Text(editing == null ? '新建歌单' : '编辑歌单'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '例如：深夜通勤',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: '描述（可选）'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                final notifier = ref.read(playlistStateProvider.notifier);
                if (editing == null) {
                  notifier.createPlaylist(
                    name: name,
                    description:
                        descController.text.trim().isEmpty
                            ? null
                            : descController.text.trim(),
                  );
                } else {
                  notifier.renamePlaylist(editing.id, name);
                }
                Navigator.pop(ctx);
              },
              child: Text(editing == null ? '创建' : '保存'),
            ),
          ],
        ),
  );
}

/// 歌单详情页。
///
/// 头图取前 4 首歌的封面拼图，压成一条 200pt 高的 banner；
/// 列表用统一的 SongRow，正在播放的行由 SongRow 自己高亮。
class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final UserPlaylist playlist;
  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(playlistStateProvider);
    final current = state.playlists.firstWhere(
      (p) => p.id == widget.playlist.id,
      orElse: () => widget.playlist,
    );
    final player = ref.read(playerControllerProvider.notifier);
    final queueNotifier = ref.read(queueStateProvider.notifier);
    final settings = ref.watch(settingsStateProvider);

    final covers =
        current.songs
            .map((s) => s.picUrl ?? '')
            .where((u) => u.isNotEmpty)
            .take(4)
            .toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: scheme.surface,
            surfaceTintColor: Colors.transparent,
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: '编辑歌单',
                onPressed:
                    () => showCreatePlaylistDialog(
                      context,
                      ref,
                      editing: current,
                    ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: '删除歌单',
                onPressed: () {
                  ref
                      .read(playlistStateProvider.notifier)
                      .deletePlaylist(current.id);
                  Navigator.pop(context);
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              title: Text(
                current.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (covers.isNotEmpty)
                    CoverCollage(urls: covers)
                  else
                    CoverImage(
                      url: '',
                      borderRadius: BorderRadius.zero,
                      fallbackIcon: Icons.queue_music_rounded,
                      fallbackIconSize: 44,
                    ),
                  const ScrimOverlay(start: 0.2, color: Color(0xF2000000)),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${current.songs.length} 首'
                      '${(current.description ?? '').isEmpty ? '' : ' · ${current.description}'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (current.songs.isNotEmpty)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 9,
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('播放全部'),
                      onPressed: () {
                        queueNotifier.replaceQueue(
                          current.songs,
                          current.songs.first,
                        );
                        player.playSong(
                          current.songs.first,
                          quality: settings.playbackQuality,
                        );
                        openNowPlaying(context);
                      },
                    ),
                ],
              ),
            ),
          ),
          if (current.songs.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: EmptyState(
                  icon: Icons.music_off_rounded,
                  title: '歌单还是空的',
                  hint: '去搜索里长按任意一首歌，选「添加到歌单」',
                  action: FilledButton.icon(
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: const Text('去搜索'),
                    // 回到首页（搜索面板所在的那一页）而不是 push 一个新的搜索页：
                    // 用户加完歌要回到这个歌单，退回一层就行。
                    onPressed:
                        () => Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst),
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final song = current.songs[index];
                return SongRow(
                  song: song,
                  index: index,
                  showArtwork: false,
                  showFavoriteAction: false,
                  onTap: () {
                    queueNotifier.replaceQueue(current.songs, song);
                    player.playSong(song, quality: settings.playbackQuality);
                    openNowPlaying(context);
                  },
                  // 长按弹菜单（收藏 / 队列 / 歌单 / MV / 移除），
                  // 尾部的「−」保留成一步移除的快捷方式。
                  onLongPress:
                      () => showSongActions(
                        context,
                        ref,
                        song,
                        removeLabel: '从歌单移除',
                        onRemove:
                            () => ref
                                .read(playlistStateProvider.notifier)
                                .removeSongFromPlaylist(current.id, song),
                      ),
                  trailing: IconButton(
                    iconSize: 19,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.remove_circle_outline_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                    onPressed:
                        () => ref
                            .read(playlistStateProvider.notifier)
                            .removeSongFromPlaylist(current.id, song),
                  ),
                );
              }, childCount: current.songs.length),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
