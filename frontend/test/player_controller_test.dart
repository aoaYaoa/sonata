import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:solara_flutter/domain/models/song.dart';
import 'package:solara_flutter/domain/state/queue_state.dart';
import 'package:solara_flutter/domain/models/stream_info.dart';
import 'package:solara_flutter/services/player_controller.dart';
import 'package:solara_flutter/services/persistent_state_service.dart';
import 'package:solara_flutter/services/storage_service.dart';
import 'package:solara_flutter/platform/audio_engine.dart';
import 'package:solara_flutter/data/solara_repository.dart';
import 'package:solara_flutter/data/api/solara_api.dart';
import 'package:solara_flutter/data/api/api_client.dart';
import 'package:solara_flutter/services/theme_controller.dart';
import 'package:dio/dio.dart';

class FakeRepo extends SolaraRepository {
  FakeRepo()
    : super(
        api: SolaraApi(client: ApiClient(baseUrl: 'https://example.com')),
        dio: Dio(),
      );

  /// 记录每首歌被取流了几次：预取如果生效，切过去时不会再请求。
  final Map<String, int> streamCalls = {};

  // playSong 直接调 fetchStream（要拿到实际档位/码率/是否试听），
  // 只覆盖 fetchSongUrl 的话会走真实网络，测试里必然抛异常。
  @override
  Future<StreamInfo> fetchStream({
    required String songId,
    required String source,
    required String quality,
    String? mediaId,
  }) async {
    streamCalls.update(songId, (n) => n + 1, ifAbsent: () => 1);
    // 让出一次事件循环，模拟真实网络往返：交接期间没有预取就会露馅。
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return StreamInfo(
      url: 'https://example.com/$songId.mp3',
      quality: '320',
      bitrate: 320000,
      ext: 'mp3',
    );
  }

  @override
  Future<String> fetchLyric({
    required String songId,
    required String source,
  }) async {
    return '[00:00.00]Hello';
  }

  @override
  Future<String> fetchPicUrl({
    required String picId,
    required String source,
    int size = 300,
  }) async {
    return 'https://example.com/pic.jpg';
  }
}

class FakeEngine implements AudioEngine {
  /// 记录调用顺序，用来验证「先 pause 再 seek」。
  final List<String> calls = [];

  bool _playing = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  double _volume = 1.0;
  double _speed = 1.0;
  final _completeController = StreamController<void>.broadcast();

  @override
  bool get isPlaying => _playing;

  @override
  Duration get position => _position;

  @override
  Duration? get duration => _duration;

  @override
  Stream<void> get onComplete => _completeController.stream;

  @override
  double get volume => _volume;

  @override
  double get speed => _speed;

  @override
  Future<void> pause() async {
    calls.add('pause');
    _playing = false;
  }

  @override
  Future<void> play() async {
    _playing = true;
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek');
    _position = position;
  }

  @override
  Future<void> setSource(String url) async {
    calls.add('setSource');
    _position = Duration.zero;
    _duration = null;
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _position = Duration.zero;
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
  }

  /// 模拟播放完毕（引擎上报 completed）。
  void fakeComplete() => _completeController.add(null);
}

class FakeThemeController extends ThemeController {
  @override
  Future<void> updateFromArtwork(String? url) async {}
}

void main() {
  // skipNext 里会预热封面进 imageCache，需要 binding 存在。
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PlayerController playSong updates state', () async {
    final controller = PlayerController(
      repository: FakeRepo(),
      engine: FakeEngine(),
      themeController: FakeThemeController(),
      persistence: PersistentStateService(storage: StorageService()),
    );
    final song = Song(
      id: '1',
      name: 'Song 1',
      artist: 'Artist',
      album: 'Album',
      picId: 'pic',
      urlId: 'url',
      lyricId: 'lyric',
      source: 'netease',
    );

    await controller.playSong(song, quality: '320');

    expect(controller.state.currentSong?.id, '1');
    expect(controller.state.isPlaying, true);

    // 歌词与封面是并行后台加载的（playSong 不阻塞返回），
    // 需要让出事件循环后再断言。
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(controller.state.lyrics.isNotEmpty, true);
  });

  Song songOf(String id) => Song(
    id: id,
    name: 'Song $id',
    artist: 'Artist',
    album: 'Album',
    picId: 'pic$id',
    urlId: 'url$id',
    lyricId: 'lyric$id',
    source: 'netease',
  );

  test('playSong 预取后面两首，切过去不再取流', () async {
    final repo = FakeRepo();
    final queue = [songOf('1'), songOf('2'), songOf('3')];
    var index = 0;
    final controller = PlayerController(
      repository: repo,
      engine: FakeEngine(),
      themeController: FakeThemeController(),
      persistence: PersistentStateService(storage: StorageService()),
      getQueue: () => queue,
      getPlayMode: () => PlayMode.list,
      getCurrentQueueIndex: () => index,
      setCurrentQueueIndex: (i) => index = i,
      getQuality: () => '320',
    );

    await controller.playSong(queue[0], quality: '320');
    // 预取是后台任务，等它跑完（每首内部 delay 5ms）
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(repo.streamCalls['1'], 1);
    expect(repo.streamCalls['2'], 1, reason: '第二首应已预取');
    expect(repo.streamCalls['3'], 1, reason: '第三首应已预取');

    await controller.skipNext(
      queue: queue,
      currentIndex: 0,
      playMode: PlayMode.list,
      quality: '320',
    );
    expect(repo.streamCalls['2'], 1, reason: '命中预取，切歌时不该再请求');
    expect(controller.state.currentSong?.id, '2');
  });

  test('播完先暂停再归零，避免上一首重播几秒', () async {
    final repo = FakeRepo();
    final queue = [songOf('1'), songOf('2')];
    var index = 0;
    final engine = FakeEngine();
    final controller = PlayerController(
      repository: repo,
      engine: engine,
      themeController: FakeThemeController(),
      persistence: PersistentStateService(storage: StorageService()),
      getQueue: () => queue,
      getPlayMode: () => PlayMode.list,
      getCurrentQueueIndex: () => index,
      setCurrentQueueIndex: (i) => index = i,
      getQuality: () => '320',
    );

    await controller.playSong(queue[0], quality: '320');
    engine.calls.clear();
    engine.fakeComplete();
    await Future<void>.delayed(const Duration(milliseconds: 5));

    // 关键顺序：pause 一定在 seek 之前，否则 completed 状态下 seek(0)
    // 会让上一首从头再唱。
    expect(engine.calls.take(2).toList(), ['pause', 'seek']);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(controller.state.currentSong?.id, '2');
  });
}
