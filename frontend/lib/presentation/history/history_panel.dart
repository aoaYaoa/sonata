import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/history_entry.dart';
import '../../domain/state/history_state.dart';
import '../../domain/state/queue_state.dart';
import '../../domain/state/settings_state.dart';
import '../../services/player_controller.dart';
import '../now_playing/open_now_playing.dart';
import '../widgets/solara_ui.dart';
import '../widgets/song_row.dart';

/// 播放历史列表。弹层（我的 → 历史）和独立页（首页「最近播放 → 全部」）共用。
class HistoryPanel extends ConsumerWidget {
  const HistoryPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final entries = ref.watch(historyStateProvider).entries;
    final player = ref.read(playerControllerProvider.notifier);
    final queue = ref.read(queueStateProvider.notifier);
    final settings = ref.watch(settingsStateProvider);

    if (entries.isEmpty) {
      return const EmptyState(
        icon: Icons.history_rounded,
        title: '还没有播放记录',
        hint: '听过的歌会自动出现在这里',
      );
    }

    final grouped = _groupByDate(entries);
    final items = <Object>[];
    for (final g in grouped) {
      items.add(g.label);
      items.addAll(g.entries);
    }
    final allSongs = entries.map((e) => e.song).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
          child: Row(
            children: [
              Text(
                '共 ${entries.length} 首',
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
                  queue.replaceQueue(allSongs, allSongs.first);
                  player.playSong(
                    allSongs.first,
                    quality: settings.playbackQuality,
                  );
                  openNowPlaying(context);
                },
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: scheme.error,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: const Text('清空'),
                onPressed: () => _confirmClear(context, ref),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 20),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              if (item is String) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                  child: Text(
                    item,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              final entry = item as HistoryEntry;
              final song = entry.song;
              return SongRow(
                song: song,
                onTap: () {
                  queue.replaceQueue(allSongs, song);
                  player.playSong(song, quality: settings.playbackQuality);
                  openNowPlaying(context);
                },
                trailing: IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.close_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                  onPressed:
                      () => ref
                          .read(historyStateProvider.notifier)
                          .removeEntry(entry),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('清空播放历史'),
            content: const Text('这个操作不能撤销。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  ref.read(historyStateProvider.notifier).clear();
                  Navigator.pop(ctx);
                },
                child: Text('清空', style: TextStyle(color: scheme.error)),
              ),
            ],
          ),
    );
  }

  List<_DateGroup> _groupByDate(List<HistoryEntry> entries) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final groups = <String, List<HistoryEntry>>{};
    for (final e in entries) {
      final d = DateTime(e.playedAt.year, e.playedAt.month, e.playedAt.day);
      final String label;
      if (d == today) {
        label = '今天';
      } else if (d == yesterday) {
        label = '昨天';
      } else if (now.difference(d).inDays < 7) {
        label = '${now.difference(d).inDays} 天前';
      } else {
        label = '${e.playedAt.month} 月 ${e.playedAt.day} 日';
      }
      groups.putIfAbsent(label, () => []).add(e);
    }
    return groups.entries
        .map((e) => _DateGroup(label: e.key, entries: e.value))
        .toList();
  }
}

class _DateGroup {
  final String label;
  final List<HistoryEntry> entries;
  const _DateGroup({required this.label, required this.entries});
}
