import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'audio_engine.dart';

class JustAudioEngine implements AudioEngine {
  final AudioPlayer _player;

  JustAudioEngine(this._player);

  @override
  Stream<void> get onComplete => _player.playerStateStream
      .map((s) => s.processingState == ProcessingState.completed)
      .distinct()
      .where((isCompleted) => isCompleted)
      .map((_) {});

  @override
  bool get isPlaying => _player.playing;

  @override
  Duration get position => _player.position;

  @override
  Duration? get duration => _player.duration;

  @override
  Future<void> play() async {
    // 上一首自然播完时，just_audio 的 `playing` 标志不会归零（Dart 侧仍是 true，
    // 原生 `_playing` 也是 YES）。这时再调 `play()` 会被它当成重复请求直接早退：
    //   - 不给原生发 play 指令；
    //   - 更关键的是不会走 `audioSession.setActive(true)` 去激活 AVAudioSession。
    // 会话一旦被系统停掉，下一首就算装好也一声不响——就是「断了」。
    //
    // 先 pause 一次把标志归位（pause 不会停会话，只有 stop() 才会），再 play，
    // 这次才是真正的一次「开始播放」：重新激活会话 + 给原生发 play。
    if (_player.playing) {
      await _player.pause();
    }
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  @override
  double get volume => _player.volume;

  @override
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
  }

  @override
  Future<void> setSource(String url) async {
    final loadedDuration = await _player.setUrl(url);
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    final uri = Uri.parse(url);
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.path.toLowerCase().endsWith('.flac')) {
      final end = _player.duration ?? loadedDuration;
      if (end != null && end > Duration.zero) {
        await _player.setClip(end: end);
      }
    }
  }

  @override
  double get speed => _player.speed;

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
  }
}
