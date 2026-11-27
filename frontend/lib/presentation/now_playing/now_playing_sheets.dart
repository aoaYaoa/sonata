import 'dart:io';

import 'package:flutter/material.dart';
import 'package:volume_controller/volume_controller.dart';

import '../../domain/models/playback_quality.dart';
import '../../domain/models/song.dart';
import '../../domain/state/settings_state.dart';
import '../../services/debug_log_bus.dart';
import '../../services/eq_service.dart';
import '../../services/player_controller.dart';
import '../../services/sleep_timer_service.dart';
import '../queue/queue_panel.dart';
import 'mv_player_screen.dart';

/// 播放页的全部弹层。
///
/// 原来这六个 sheet（音质 / 音效 / 倍速 / 音量 / 定时 / 歌曲信息 / 队列）
/// 都长在 `now_playing_screen.dart` 里，那个文件因此涨到 1500 行——
/// 改一个格子的版式要先在六个弹层之间翻过。弹层和版式没有耦合，
/// 拆出来之后主文件只剩「这一屏怎么排」。

void showQualityPicker(
  BuildContext context, {
  required String current,
  required PlayerController controller,
  required SettingsStateNotifier settingsNotifier,
}) {
  // 只列当前歌曲真能拿到的档位：列全档会让用户点到拿不到的档，
  // 白等一次失败（QQ 匿名态就是这样）。
  final items = PlaybackQuality.availableFor(controller.currentSong);

  showModalBottomSheet<void>(
    context: context,
    builder:
        (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetTitle(title: '音质选择', context: ctx),
              ...items.map(
                (q) => _CheckTile(
                  label: PlaybackQuality.label(q),
                  selected: current == q,
                  onTap: () async {
                    settingsNotifier.setPlaybackQuality(q);
                    Navigator.pop(ctx);
                    // 立刻按新档位重载当前曲目并保持进度；
                    // 只存设置不重载，用户听到的还是旧流。
                    await controller.applyQuality(q);
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
  );
}

void showSpeedPicker(
  BuildContext context, {
  required double currentSpeed,
  required PlayerController controller,
  required SettingsStateNotifier settingsNotifier,
}) {
  const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  showModalBottomSheet<void>(
    context: context,
    builder:
        (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetTitle(title: '播放速度', context: ctx),
              ...speeds.map(
                (s) => _CheckTile(
                  label: s == 1.0 ? '正常 (1.0x)' : '${s}x',
                  selected: currentSpeed == s,
                  onTap: () {
                    controller.setSpeed(s);
                    settingsNotifier.setPlaybackSpeed(s);
                    Navigator.pop(ctx);
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
  );
}

void showEqPicker(
  BuildContext context, {
  required String currentPreset,
  required SettingsStateNotifier settingsNotifier,
}) {
  showModalBottomSheet<void>(
    context: context,
    builder:
        (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetTitle(title: '音效', context: ctx),
              ...EqService.presets.map(
                (preset) => _CheckTile(
                  label: preset.label,
                  selected: currentPreset == preset.id,
                  onTap: () {
                    settingsNotifier.setEqPreset(preset.id);
                    EqService.applyPreset(preset.id);
                    Navigator.pop(ctx);
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
  );
}

/// 音量弹层。iOS/Android 走系统音量（并跟随硬件键的实时变化），
/// 桌面走应用内音量。
Future<void> showVolumeSheet(
  BuildContext context, {
  required SettingsState settings,
  required SettingsStateNotifier settingsNotifier,
}) async {
  final useSystemVolume =
      !Platform.isMacOS && !Platform.isWindows && !Platform.isLinux;
  var vol = settings.volume;
  if (useSystemVolume) {
    try {
      vol = await VolumeController().getVolume();
    } catch (e) {
      DebugLogBus.add('[NowPlaying] 读取系统音量失败，回退到应用内音量: $e');
    }
  }
  if (!context.mounted) return;
  showModalBottomSheet<void>(
    context: context,
    builder:
        (_) => _VolumeSheet(
          initialVolume: vol,
          useSystemVolume: useSystemVolume,
          onChanged: settingsNotifier.setVolume,
        ),
  );
}

void showSongInfo(BuildContext context, Song? song) {
  if (song == null) return;
  showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder:
        (ctx) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          ctx,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '歌曲信息',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _InfoRow(label: '歌曲', value: song.name),
                  _InfoRow(label: '艺术家', value: song.artist),
                  _InfoRow(label: '专辑', value: song.album),
                  _InfoRow(label: '来源', value: _sourceFullLabel(song.source)),
                  if ((song.mvId ?? '').isNotEmpty) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.video_library_outlined),
                        label: const Text('播放 MV'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.of(ctx).push(
                            MaterialPageRoute(
                              builder:
                                  (_) => MvPlayerScreen(
                                    mvId: song.mvId!,
                                    source: song.source,
                                    songName: song.name,
                                    artist: song.artist,
                                  ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
  );
}

void showSleepTimerSheet(
  BuildContext context,
  SleepTimerState timerState,
  SleepTimerNotifier timerNotifier,
) {
  const options = [
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 45),
    Duration(minutes: 60),
    Duration(minutes: 90),
  ];
  showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder:
        (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '睡眠定时',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (timerState.active)
                      TextButton(
                        onPressed: () {
                          timerNotifier.cancel();
                          Navigator.pop(ctx);
                        },
                        child: const Text('取消定时'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children:
                      options.map((d) {
                        final mins = d.inMinutes;
                        final isActive =
                            timerState.active &&
                            timerState.remaining != null &&
                            (timerState.remaining!.inMinutes - mins).abs() < 2;
                        return ChoiceChip(
                          label: Text('$mins 分钟'),
                          selected: isActive,
                          onSelected: (_) {
                            timerNotifier.start(d);
                            Navigator.pop(ctx);
                          },
                        );
                      }).toList(),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
  );
}

void showQueueSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (_) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          builder:
              (ctx, _) => Container(
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // 标题交给 QueuePanel 自己那行「N 首 · 正在播放第 N 首」，
                    // 外层再写一个「播放队列」只是重复两行字。
                    const Expanded(child: QueuePanel()),
                  ],
                ),
              ),
        ),
  );
}

String _sourceFullLabel(String source) {
  // 放在这里而不是 import MusicSource：这个文件只服务播放页，
  // 多引一个模型只为一行 toString 不值得，用短名反查即可。
  return const {
        'netease': '网易云音乐',
        'tencent': 'QQ 音乐',
        'kugou': '酷狗音乐',
        'bilibili': '哔哩哔哩',
        'youtube': 'YouTube',
        'jamendo': 'Jamendo',
        'local': '本地文件',
      }[source] ??
      source;
}

class _SheetTitle extends StatelessWidget {
  final String title;
  final BuildContext context;
  const _SheetTitle({required this.title, required this.context});

  @override
  Widget build(BuildContext _) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CheckTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing:
          selected
              ? Icon(
                Icons.check_rounded,
                color: Theme.of(context).colorScheme.primary,
              )
              : null,
      onTap: onTap,
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _VolumeSheet extends StatefulWidget {
  final double initialVolume;
  final bool useSystemVolume;
  final ValueChanged<double> onChanged;

  const _VolumeSheet({
    required this.initialVolume,
    required this.useSystemVolume,
    required this.onChanged,
  });

  @override
  State<_VolumeSheet> createState() => _VolumeSheetState();
}

class _VolumeSheetState extends State<_VolumeSheet> {
  late double _vol;

  @override
  void initState() {
    super.initState();
    _vol = widget.initialVolume;
    if (widget.useSystemVolume) {
      VolumeController().listener((v) {
        if (mounted) setState(() => _vol = v);
      });
    }
  }

  @override
  void dispose() {
    if (widget.useSystemVolume) {
      VolumeController().removeListener();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '音量',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  Icons.volume_down,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                Expanded(
                  child: Slider(
                    value: _vol.clamp(0.0, 1.0),
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    label: '${(_vol * 100).round()}%',
                    onChanged: (v) {
                      setState(() => _vol = v);
                      if (widget.useSystemVolume) {
                        VolumeController().setVolume(v);
                      }
                      widget.onChanged(v);
                    },
                  ),
                ),
                Icon(
                  Icons.volume_up,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
