import '../models/song.dart';
import '../models/lyric_line.dart';

class PlayerState {
  final Song? currentSong;
  final bool isPlaying;
  final Duration position;
  final Duration? duration;
  final List<LyricLine> lyrics;
  final int currentLyricIndex;
  final String? artworkUrl;
  final String? error;
  final double speed;

  /// 实际拿到的音质档位（'128'/'320'/'flac'）与实际码率。
  ///
  /// 用户选的是「想要什么」，这里是「真的拿到什么」——QQ 匿名态只有 128k、
  /// 酷狗会员曲会降到 128k，UI 显示这一对值才不会骗人。
  final String actualQuality;
  final int actualBitrate;

  /// true 表示当前播的是试听片段（QQ 无权限时回落 60 秒）。
  final bool isPreview;

  const PlayerState({
    required this.currentSong,
    required this.isPlaying,
    required this.position,
    this.duration,
    required this.lyrics,
    required this.currentLyricIndex,
    required this.artworkUrl,
    required this.error,
    this.speed = 1.0,
    this.actualQuality = '',
    this.actualBitrate = 0,
    this.isPreview = false,
  });

  /// [clearArtworkUrl] 为 true 时将 artworkUrl 重置为 null（因为 String? 的 copyWith 无法通过传 null 来清除）
  PlayerState copyWith({
    Song? currentSong,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    List<LyricLine>? lyrics,
    int? currentLyricIndex,
    String? artworkUrl,
    bool clearArtworkUrl = false,
    String? error,
    double? speed,
    String? actualQuality,
    int? actualBitrate,
    bool? isPreview,
  }) {
    return PlayerState(
      currentSong: currentSong ?? this.currentSong,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      lyrics: lyrics ?? this.lyrics,
      currentLyricIndex: currentLyricIndex ?? this.currentLyricIndex,
      artworkUrl: clearArtworkUrl ? null : (artworkUrl ?? this.artworkUrl),
      error: error,
      speed: speed ?? this.speed,
      actualQuality: actualQuality ?? this.actualQuality,
      actualBitrate: actualBitrate ?? this.actualBitrate,
      isPreview: isPreview ?? this.isPreview,
    );
  }

  static PlayerState initial() {
    return const PlayerState(
      currentSong: null,
      isPlaying: false,
      position: Duration.zero,
      duration: null,
      lyrics: [],
      currentLyricIndex: -1,
      artworkUrl: null,
      error: null,
    );
  }
}
