import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../domain/state/settings_state.dart';
import '../../domain/state/queue_state.dart';
import '../../services/image_headers.dart' show sizedCoverUrl;
import '../../services/player_controller.dart';
import '../now_playing/open_now_playing.dart';

/// 常驻播放条。
///
/// 视觉目标：像一张「悬浮的小唱片」，而不是一条工具栏。
///  - 毛玻璃底 + 顶部一条极细进度线，和下面的导航胶囊连成一体；
///  - 封面 44pt 圆角 12，标题一行、歌手一行，右侧只留三个控制键；
///  - 播放键用实心强调色，是全屏唯一的实心圆按钮。
class PlayerBar extends ConsumerStatefulWidget {
  const PlayerBar({super.key});

  @override
  ConsumerState<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends ConsumerState<PlayerBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _playPauseController;

  /// 拖动进度时的临时比例，null 表示没在拖（用真实播放进度）。
  double? _dragValue;

  /// 拖动开始前是不是在播：拖完要保持原来的状态，不能一拖就自动播起来。
  bool _wasPlayingBeforeSeek = false;

  @override
  void initState() {
    super.initState();
    _playPauseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _playPauseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final settings = ref.watch(settingsStateProvider);
    final queueState = ref.watch(queueStateProvider);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (state.isPlaying) {
      _playPauseController.forward();
    } else {
      _playPauseController.reverse();
    }

    final position = state.position;
    final duration = state.duration ?? Duration.zero;
    final progress =
        duration.inMilliseconds > 0
            ? (position.inMilliseconds / duration.inMilliseconds).clamp(
              0.0,
              1.0,
            )
            : 0.0;

    final hasSong = state.currentSong != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: hasSong ? () => openNowPlaying(context) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              decoration: BoxDecoration(
                color:
                    isDark
                        ? SolaraColors.darkSurfaceHigh.withValues(alpha: 0.82)
                        : Colors.white.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color:
                      isDark
                          ? Colors.white.withValues(alpha: 0.07)
                          : Colors.black.withValues(alpha: 0.05),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 进度：压在最小的位置，不抢视觉重心。
                  // 可横向拖动跳转——原来只是一条 LinearProgressIndicator，
                  // 想跳到某处必须先点进播放页，多一步。
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                    child: LayoutBuilder(
                      builder:
                          (context, constraints) => GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragStart:
                                duration.inMilliseconds <= 0
                                    ? null
                                    : (d) => setState(() {
                                      _wasPlayingBeforeSeek = state.isPlaying;
                                      _dragValue = (d.localPosition.dx /
                                              constraints.maxWidth)
                                          .clamp(0.0, 1.0);
                                    }),
                            onHorizontalDragUpdate:
                                duration.inMilliseconds <= 0
                                    ? null
                                    : (d) => setState(() {
                                      _dragValue = (d.localPosition.dx /
                                              constraints.maxWidth)
                                          .clamp(0.0, 1.0);
                                    }),
                            onHorizontalDragEnd:
                                duration.inMilliseconds <= 0
                                    ? null
                                    : (_) {
                                      final ratio = _dragValue;
                                      setState(() => _dragValue = null);
                                      if (ratio == null) return;
                                      controller.seekTo(
                                        Duration(
                                          milliseconds:
                                              (ratio * duration.inMilliseconds)
                                                  .round(),
                                        ),
                                      );
                                      // 拖动时如果本来是播放中，连续播放不中断；
                                      // 本来暂停的就保持暂停（Seek 会唤醒播放器）。
                                      if (!_wasPlayingBeforeSeek) {
                                        controller.toggle();
                                      }
                                    },
                            // 命中区域上下各扩 8pt：2.5pt 的线用手指点不准。
                            child: SizedBox(
                              height: 18,
                              child: Align(
                                alignment: Alignment.center,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: _dragValue ?? progress,
                                    minHeight: 2.5,
                                    backgroundColor: scheme.onSurface
                                        .withValues(alpha: 0.08),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      scheme.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                    child: Row(
                      children: [
                        _ArtworkThumbnail(
                          artworkUrl: state.artworkUrl,
                          size: 44,
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 280),
                                child: Text(
                                  state.currentSong?.name ?? '未在播放',
                                  key: ValueKey(state.currentSong?.id),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        hasSong
                                            ? scheme.onSurface
                                            : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              if (hasSong) ...[
                                const SizedBox(height: 2),
                                Text(
                                  state.currentSong!.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed:
                              queueState.songs.isEmpty
                                  ? null
                                  : () => controller.skipNext(
                                    queue: queueState.songs,
                                    currentIndex: queueState.currentIndex,
                                    playMode: queueState.playMode,
                                    quality: settings.playbackQuality,
                                  ),
                          icon: const Icon(Icons.skip_next_rounded),
                          iconSize: 26,
                          splashRadius: 20,
                          color: scheme.onSurface,
                          disabledColor: scheme.onSurface.withValues(
                            alpha: 0.25,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                        ),
                        const SizedBox(width: 4),
                        _PlayPauseButton(
                          isPlaying: state.isPlaying,
                          enabled: hasSong,
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            controller.toggle();
                          },
                        ),
                        const SizedBox(width: 2),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtworkThumbnail extends StatelessWidget {
  final String? artworkUrl;
  final double size;
  const _ArtworkThumbnail({this.artworkUrl, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(12);

    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: radius,
      ),
      child: Icon(
        Icons.graphic_eq_rounded,
        size: size * 0.44,
        color: scheme.onSurfaceVariant,
      ),
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 360),
      child:
          (artworkUrl ?? '').isEmpty
              ? placeholder
              : ClipRRect(
                key: ValueKey(artworkUrl),
                borderRadius: radius,
                child: Image.network(
                  sizedCoverUrl(artworkUrl!, size: 160),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  cacheWidth: (size * 3).toInt(),
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => placeholder,
                ),
              ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final bool enabled;
  final VoidCallback onPressed;
  const _PlayPauseButton({
    required this.isPlaying,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg =
        enabled ? scheme.primary : scheme.onSurface.withValues(alpha: 0.08);
    final fg =
        enabled
            ? SolaraColors.onAccent(scheme.primary)
            : scheme.onSurface.withValues(alpha: 0.3);

    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onPressed : null,
        child: SizedBox(
          width: 42,
          height: 42,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder:
                (child, anim) => ScaleTransition(scale: anim, child: child),
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey(isPlaying),
              color: fg,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}
