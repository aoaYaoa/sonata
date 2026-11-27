import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:solara_flutter/services/audio_handler.dart';

class _TestPlayer extends Fake implements AudioPlayer {
  final _events = StreamController<PlaybackEvent>.broadcast(sync: true);

  @override
  ProcessingState processingState = ProcessingState.idle;

  @override
  bool playing = false;

  @override
  Stream<PlaybackEvent> get playbackEventStream => _events.stream;

  @override
  Stream<PlayerState> get playerStateStream => const Stream.empty();

  @override
  Duration get position => Duration.zero;

  @override
  Duration get bufferedPosition => Duration.zero;

  @override
  double get speed => 1;

  void emit(ProcessingState state, {required bool isPlaying}) {
    processingState = state;
    playing = isPlaying;
    _events.add(PlaybackEvent(processingState: state));
  }

  @override
  Future<void> dispose() => _events.close();
}

void main() {
  late _TestPlayer player;
  late SolaraAudioHandler handler;

  setUp(() {
    player = _TestPlayer();
    handler = SolaraAudioHandler(player);
    addTearDown(player.dispose);
    player.emit(ProcessingState.ready, isPlaying: true);
  });

  test('自动切歌换源时的 idle 对媒体服务上报 loading', () {
    handler.beginSwitching();
    player.emit(ProcessingState.idle, isPlaying: true);

    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.loading,
    );
    expect(handler.playbackState.value.playing, isTrue);

    player.emit(ProcessingState.ready, isPlaying: true);
    handler.endSwitching();

    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.ready,
    );
  });

  test('换源失败结束交接时立即恢复真实状态', () {
    handler.beginSwitching();
    player.emit(ProcessingState.idle, isPlaying: true);
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.loading,
    );

    handler.endSwitching();

    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
  });

  test('即使仍在交接，停止播放也对媒体服务上报 idle', () {
    handler.beginSwitching();
    player.emit(ProcessingState.idle, isPlaying: false);

    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
    expect(handler.playbackState.value.playing, isFalse);
  });
}
