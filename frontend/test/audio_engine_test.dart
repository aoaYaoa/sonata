import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:solara_flutter/platform/audio_engine.dart';
import 'package:solara_flutter/platform/just_audio_engine.dart';

class _FlacPlayer extends Fake implements AudioPlayer {
  final loadedDuration = const Duration(minutes: 4, seconds: 55);
  final clipEnds = <Duration?>[];

  @override
  Duration? get duration => loadedDuration;

  @override
  Future<Duration?> setUrl(
    String url, {
    Map<String, String>? headers,
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async => loadedDuration;

  @override
  Future<Duration?> setClip({
    Duration? start,
    Duration? end,
    dynamic tag,
  }) async {
    clipEnds.add(end);
    return loadedDuration;
  }
}

void main() {
  test('AudioEngine interface exposes required methods', () {
    final engine = FakeAudioEngine();
    expect(engine.isPlaying, false);
    engine.play();
    expect(engine.isPlaying, true);
    engine.pause();
    expect(engine.isPlaying, false);
    engine.seek(Duration(seconds: 10));
    expect(engine.position, const Duration(seconds: 10));
  });

  test(
    'iOS sets a native endpoint for a remote FLAC with known duration',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final player = _FlacPlayer();
      final engine = JustAudioEngine(player);

      await engine.setSource('https://example.com/track.flac?signature=value');

      expect(player.clipEnds, [player.loadedDuration]);
      await engine.setSource('https://example.com/track.mp3');
      await engine.setSource('file:///track.flac');
      expect(player.clipEnds, [player.loadedDuration]);
    },
  );
}
