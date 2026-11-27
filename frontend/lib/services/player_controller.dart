import 'dart:async';
import 'dart:math';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/song.dart';
import '../domain/models/stream_info.dart';
import '../domain/state/history_state.dart';
import '../domain/state/player_state.dart';
import '../domain/state/settings_state.dart';
import '../services/providers.dart';
import '../services/sleep_timer_service.dart';
import '../domain/state/queue_state.dart';
import '../data/solara_repository.dart';
import '../data/providers.dart';
import '../platform/audio_engine.dart';
import '../platform/just_audio_engine.dart';
import 'debug_log_bus.dart';
import '../services/lyric_parser.dart';
import '../services/theme_controller.dart';
import '../services/app_config.dart';
import '../services/persistent_state_service.dart';
import '../main.dart' show nowPlayingHandler, sharedPlayer;

class PlayerController extends StateNotifier<PlayerState> {
  final SolaraRepository repository;
  final AudioEngine engine;
  final ThemeController themeController;
  final PersistentStateService persistence;
  final void Function(Song)? onSongPlayed;
  Timer? _timer;
  Timer? _durationTimer;
  StreamSubscription<void>? _completeSub;
  List<Song> Function()? getQueue;
  PlayMode Function()? getPlayMode;
  int Function()? getCurrentQueueIndex;
  void Function(int)? setCurrentQueueIndex;
  String Function()? getQuality;
  bool _isLoading = false;
  bool _isSwitching = false;

  /// 交接代次。用户在这期间手动切歌时 +1，让自动交接那一路知道
  /// 自己已经过时，不要再补一次 skipNext（否则连跳两首）。
  int _advanceGeneration = 0;

  /// 预取到的流地址。key = `source:id:tier`。
  ///
  /// 命中就用完即删：直链是带时效的临时签名，放久了会 403。
  final Map<String, _PreloadEntry> _preload = {};
  final Set<String> _preloadInFlight = {};

  /// 往后预取几首。
  static const int _preloadAhead = 2;

  /// 预取结果的保鲜期，超过就当没有（直链签名一般 10~20 分钟过期）。
  static const Duration _preloadTtl = Duration(minutes: 10);

  /// 缓存上限，防止连续切歌把内存堆满。
  static const int _preloadMaxEntries = 8;

  /// 距结尾还剩多久时做一次「直链是否快过期」的确认。
  static const Duration _preloadRefreshWindow = Duration(seconds: 30);

  /// 已经补取过的歌（`source:id`），保证每首歌只补一次。
  String? _refreshedForSong;

  /// 随机模式下「已经预取好的下一首」。
  ///
  /// 顺序模式里下一首是确定的，预取哪首就播哪首。随机模式如果不记住这次抽到
  /// 的是哪一首，预取 A 却抽到 B，那张直链就白取了——预取在随机模式下等于没做。
  /// 所以这里先抽签、预取、切歌时优先兑现这张签。
  int? _plannedRandomNext;
  Duration? _restoredPosition;
  int _tickCount = 0;

  PlayerController({
    required this.repository,
    required this.engine,
    required this.themeController,
    required this.persistence,
    this.onSongPlayed,
    this.getQueue,
    this.getPlayMode,
    this.getCurrentQueueIndex,
    this.setCurrentQueueIndex,
    this.getQuality,
  }) : super(PlayerState.initial()) {
    // 热重载后原生播放器可能还在播放，先停掉保持状态一致
    if (engine.isPlaying) {
      engine.stop();
    }
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _tick();
    });
    _completeSub = engine.onComplete.listen((_) {
      _onSongComplete();
    });
  }

  void _onSongComplete() {
    // 防止 seek(Duration.zero) 触发二次 complete 事件导致重复切歌
    if (_isSwitching) return;
    _isSwitching = true;
    nowPlayingHandler?.beginSwitching();
    final generation = ++_advanceGeneration;
    unawaited(_advanceAfterComplete(generation));
  }

  /// 播完 → 切下一首。
  ///
  /// 顺序是「先 pause（**不 seek**）→ 再换源 → 最后 play」，三个动作各治一个坑：
  ///  1. 不 pause：just_audio 自然播完时不会把 `playing` 置回 false，而 `play()`
  ///     第一行就是 `if (playing) return;`。标志还是 true 时下一首的 play() 直接
  ///     早退——既不给原生发 play，也不会 `audioSession.setActive(true)` 激活
  ///     AVAudioSession。会话没激活，音频装好了也一声不响，就是「断了」。
  ///  2. seek(0)：completed 状态下回零等于让上一首从头再唱，还要等下一首的流
  ///     回来（冷启动 600ms~2s）才切走 →「重播几秒才跳走」。
  ///  3. 只 pause：音频早已结束，没有声音被截断；`_playing` 归零后 setSource 的
  ///     load 不会自动设 rate，play() 才真的执行一次（激活会话 + 发 play）。
  Future<void> _advanceAfterComplete(int generation) async {
    try {
      await engine.pause();
    } catch (e) {
      DebugLogBus.add('[PlayerController] 交接前暂停失败: $e');
    }
    // 用户已经手动切过歌了：这次自动交接作废。
    if (generation != _advanceGeneration) return;
    final queue = getQueue?.call() ?? [];
    final playMode = getPlayMode?.call() ?? PlayMode.list;
    final currentIndex = getCurrentQueueIndex?.call() ?? 0;
    // 兜底用 'auto'，与 SettingsState 默认值一致：写死 '320' 会让没注入
    // getQuality 的场景（如恢复会话后首次播放）悄悄降档。
    final quality = getQuality?.call() ?? 'auto';
    if (queue.isEmpty || playMode == PlayMode.single) {
      final song = state.currentSong;
      if (song == null) {
        _isSwitching = false;
        nowPlayingHandler?.endSwitching();
        return;
      }
      await playSong(song, quality: quality);
      return;
    }
    await skipNext(
      queue: queue,
      currentIndex: currentIndex,
      playMode: playMode,
      quality: quality,
    );
  }

  void _tick() {
    // 加载新歌曲期间不更新，避免引擎返回旧歌曲的 position/duration 覆盖新状态
    if (_isLoading) return;
    // 同步引擎播放状态（被其他 app 打断时引擎会暂停，需及时反映到 UI）
    final enginePlaying = engine.isPlaying;
    if (enginePlaying != state.isPlaying && !_isLoading) {
      state = state.copyWith(isPlaying: enginePlaying);
    }
    // 引擎未加载（duration为null且未播放）时不更新 position/duration，保留启动恢复的值
    if (engine.duration == null && !enginePlaying) return;
    final position = engine.position;
    final duration = engine.duration ?? state.duration;
    if (position != state.position || duration != state.duration) {
      final currentIndex = _resolveLyricIndex(state.lyrics, position);
      state = state.copyWith(
        position: position,
        duration: duration,
        currentLyricIndex: currentIndex,
      );
    }
    // 临近结尾补一次预取：直链是带时效的签名，一首十几分钟的歌播下来，
    // 开头取的那张可能已经过期。这里只看「快过期了没有」，没过期什么都不做。
    _refreshSoonExpiringPreload(duration ?? Duration.zero);

    // 每10次tick（约5秒）自动保存播放进度，应对划掉app没暂停的情况
    _tickCount++;
    if (_tickCount >= 10 && state.isPlaying && state.currentSong != null) {
      _tickCount = 0;
      persistence
          .savePlaybackPosition(
            position: state.position,
            duration: state.duration,
          )
          .ignore();
    }
  }

  int _resolveLyricIndex(List lyrics, Duration position) {
    if (lyrics.isEmpty) return -1;
    for (var i = lyrics.length - 1; i >= 0; i--) {
      final line = lyrics[i];
      if (line.time <= position) {
        return i;
      }
    }
    return -1;
  }

  /// 是否必须走后端代理播放。
  ///
  /// B站/YouTube 的直链带 Referer 校验；酷狗 trackercdn v1 给的
  /// fsvippc.tx.kugou.com 只有 HTTP（443 端口开着但 TLS 握手失败），
  /// iOS ATS 会直接拒绝。QQ 与网易云的 HTTPS 直链可以直连。
  static bool _needsProxy(String source, String url) {
    if (!url.startsWith('http')) return false;
    if (source == 'bilibili' || source == 'youtube') return true;
    if (source == 'kugou' && url.startsWith('http://')) return true;
    return false;
  }

  /// 当前曲目。UI 需要读它来决定音质菜单里列出哪些档位，
  /// 但不应直接碰 `state`（StateNotifier 的保护成员）。
  Song? get currentSong => state.currentSong;

  /// 把「用户想要的档位」翻译成「这次实际要请求的档位 + 该档位的标识」。
  ///
  /// Song.altIds 里只有确实存在且有权限的档位，所以降级在这里发生：
  /// 选 flac 但没有 flac 就退 320，没有 320 就退 128。
  /// auto 取表里最高的那一档。
  ({String quality, String? mediaId}) _resolveStreamPlan(
    Song song,
    String requested,
  ) {
    final alt = song.altIds;
    final want = requested.toLowerCase();

    if (want == 'auto') {
      for (final tier in const ['flac', '320', '128']) {
        final id = alt[tier];
        if (id != null && id.isNotEmpty) {
          return (quality: tier, mediaId: id);
        }
      }
      // 没有 alt 表（老数据或非酷狗/QQ 源）时交给后端自己挑
      return (quality: 'auto', mediaId: song.mediaId);
    }

    if (alt.isEmpty) {
      // 非酷狗/QQ 源，或老缓存里没有 alt 表：把 mediaId 交给后端反查
      return (quality: requested, mediaId: song.mediaId);
    }

    if (alt[want] != null && alt[want]!.isNotEmpty) {
      return (quality: want, mediaId: alt[want]);
    }
    // 目标档位不可用：按 flac → 320 → 128 的顺序找最近的可播档
    final order =
        want == 'flac'
            ? const ['320', '128']
            : (want == '320' ? const ['128'] : const ['320', 'flac']);
    for (final tier in order) {
      final id = alt[tier];
      if (id != null && id.isNotEmpty) {
        return (quality: tier, mediaId: id);
      }
    }
    return (quality: '128', mediaId: alt['128'] ?? song.mediaId);
  }

  /// 切换当前歌曲的音质并立刻生效。
  ///
  /// 只改设置不重新取流的话，用户点了「320」但听到的还是旧流 —— 这是
  /// 「音质选项是假的」的根源。这里保持播放进度原地重载。
  Future<void> applyQuality(String quality) async {
    final song = state.currentSong;
    final wasPlaying = state.isPlaying;
    final position = state.position;
    if (song == null) return;

    // 本地文件没有音质概念，只记住选择
    if (song.source == 'local') return;

    await playSong(
      song,
      quality: quality,
      seekTo: position > Duration.zero ? position : null,
    );
    if (!wasPlaying) {
      await engine.pause();
      state = state.copyWith(isPlaying: false);
    }
  }

  Future<void> playSong(
    Song song, {
    required String quality,
    Duration? seekTo,
  }) async {
    _isLoading = true;
    // 任何一次主动加载都让上一轮「播完自动交接」作废
    _advanceGeneration++;
    // 上一轮抽的「下一首」也作废：本次 playSong 会重新预取并重新抽签。
    _plannedRandomNext = null;
    // 保留旧封面，切歌过渡期间用于锁屏/灵动岛显示
    final previousArtworkUrl = state.artworkUrl;

    // 是否是同一首歌（恢复播放）：保留 position/duration；切换新歌才清零
    final isSameSong =
        state.currentSong?.id == song.id &&
        state.currentSong?.source == song.source;
    // 完整重置状态：直接构造新 PlayerState，避免 copyWith 的 nullable 遗留问题
    state = PlayerState(
      currentSong: song,
      isPlaying: state.isPlaying,
      position: isSameSong ? state.position : Duration.zero,
      duration: isSameSong ? state.duration : null,
      lyrics: const [],
      currentLyricIndex: -1,
      artworkUrl: previousArtworkUrl, // 保留旧封面直到新封面加载完
      error: null,
    );

    // 自动同步队列索引
    final queue = getQueue?.call() ?? [];
    final songIndex = queue.indexWhere((s) => s.id == song.id);
    if (songIndex >= 0) {
      setCurrentQueueIndex?.call(songIndex);
    }

    // 预取必须在这里发起，和本曲的取流并行跑。
    //
    // 之前放在 playSong 尾部（`await engine.setSource(url)` 之后），那一步要等
    // 音频头解析完才算「装好」——慢网 + 大文件（50MB 的 FLAC）能拖几秒。
    // 那几秒正好是预取该跑的时间，浪费掉了就等于「临播才去取」。
    // 放到这里之后，两首的直链和本曲的直链同时在路上，歌还没唱几秒就已经备齐了。
    _preloadUpcoming(
      queue: queue,
      currentIndex:
          songIndex >= 0 ? songIndex : (getCurrentQueueIndex?.call() ?? 0),
      playMode: getPlayMode?.call() ?? PlayMode.list,
      quality: quality,
    );

    // 立即计算封面 URL（无需网络请求）
    String? immediateArtworkUrl;
    if (song.picUrl != null && song.picUrl!.isNotEmpty) {
      final encoded = Uri.encodeComponent(song.picUrl!);
      immediateArtworkUrl = '${AppConfig.baseUrl}/imgproxy?url=$encoded';
    } else if (song.picId.isNotEmpty) {
      // 直接构建代理 URL，与 fetchPicUrl 返回结果一致，避免网络请求延迟
      final proxyUri = repository.buildPicProxyUrl(
        picId: song.picId,
        source: song.source,
      );
      immediateArtworkUrl = proxyUri;
    }
    immediateArtworkUrl ??= previousArtworkUrl;

    // 更新锁屏/通知栏信息
    nowPlayingHandler?.setNowPlaying(
      title: song.name,
      artist: song.artist,
      artworkUrl: immediateArtworkUrl,
    );

    try {
      String url;
      String actualQuality = '';
      int actualBitrate = 0;
      bool isPreview = false;
      if (song.source == 'local') {
        // 本地文件直接用 file:// URI
        url =
            song.urlId.startsWith('file://')
                ? song.urlId
                : 'file://${song.urlId}';
      } else if (song.source == 'jamendo' && song.urlId.startsWith('http')) {
        // Jamendo urlId 直接是 MP3 URL
        url = song.urlId;
      } else {
        final resolved = await _resolveStream(song, quality);
        url = resolved.url;
        actualQuality = resolved.quality;
        actualBitrate = resolved.bitrate;
        isPreview = resolved.preview;
      }
      DebugLogBus.add(
        '[PlayerController] 准备播放 ${song.name} '
        '($song.source) quality=$actualQuality preview=$isPreview',
      );
      try {
        await engine.setSource(url);
        DebugLogBus.add(
          '[PlayerController] setSource ok, duration=${engine.duration}',
        );
      } catch (e) {
        // 预取直链是带时效的签名，放久了会 403；这里退回现场重取一次。
        // 只有非本地/非 Jamendo 直链才有「重取」这回事。
        if (song.source == 'local' ||
            (song.source == 'jamendo' && song.urlId.startsWith('http'))) {
          rethrow;
        }
        DebugLogBus.add('[PlayerController] 直链失效，重取: $e');
        final retried = await _resolveStream(song, quality, usePreload: false);
        url = retried.url;
        actualQuality = retried.quality;
        actualBitrate = retried.bitrate;
        isPreview = retried.preview;
        await engine.setSource(url);
      }
      engine.play().catchError((e) {
        DebugLogBus.add('[PlayerController] play() error (ignored): $e');
      });

      // 如果有指定起始位置，在解除 loading 锁之前 seek，避免 _tick() 用0覆盖
      if (seekTo != null && seekTo > Duration.zero) {
        await engine.seek(seekTo);
      }
      // 引擎就绪，解除 loading 锁，让 _tick() 开始同步
      _isLoading = false;
      _isSwitching = false;
      nowPlayingHandler?.endSwitching();
      state = state.copyWith(
        isPlaying: true,
        position: seekTo ?? state.position,
        actualQuality: actualQuality,
        actualBitrate: actualBitrate,
        isPreview: isPreview,
      );

      // 立即更新锁屏/灵动岛，使用已知封面和 duration
      nowPlayingHandler?.setNowPlaying(
        title: song.name,
        artist: song.artist,
        artworkUrl: immediateArtworkUrl,
        duration: engine.duration,
      );
      // 后台等待 duration 可用后再次更新（just_audio 异步加载）
      _updateDurationWhenReady(song, immediateArtworkUrl);

      // 并行加载歌词 + 封面 URL，互不阻塞
      final lyricFuture = repository
          .fetchLyric(
            songId: song.lyricId.isNotEmpty ? song.lyricId : song.id,
            source: song.source,
          )
          .then((raw) {
            if (state.currentSong?.id == song.id) {
              state = state.copyWith(lyrics: LyricParser.parse(raw));
            }
          })
          .catchError((_) {});

      final artworkFuture = () async {
        try {
          String? realArtworkUrl;
          if (song.picUrl != null && song.picUrl!.isNotEmpty) {
            final encoded = Uri.encodeComponent(song.picUrl!);
            realArtworkUrl = '${AppConfig.baseUrl}/imgproxy?url=$encoded';
          } else if (song.picId.isNotEmpty) {
            final fetched = await repository.fetchPicUrl(
              picId: song.picId,
              source: song.source,
            );
            if (fetched.isNotEmpty) {
              if (fetched.startsWith('http') &&
                  (fetched.contains('.126.net') ||
                      fetched.contains('.163.com') ||
                      fetched.contains('.qq.com'))) {
                realArtworkUrl =
                    '${AppConfig.baseUrl}/imgproxy?url=${Uri.encodeComponent(fetched)}';
              } else {
                realArtworkUrl = fetched;
              }
            }
          }
          final artworkUrl = realArtworkUrl ?? immediateArtworkUrl ?? '';
          if (artworkUrl.isNotEmpty && state.currentSong?.id == song.id) {
            await themeController.updateFromArtwork(artworkUrl);
            if (state.currentSong?.id == song.id) {
              state = state.copyWith(artworkUrl: artworkUrl);
              nowPlayingHandler?.setNowPlaying(
                title: song.name,
                artist: song.artist,
                artworkUrl: artworkUrl,
                duration: engine.duration,
              );
            }
          }
        } catch (e) {
          DebugLogBus.add('[PlayerController] 封面/主题加载失败: $e');
        }
      }();

      // 歌词和封面完全后台加载，不阻塞 playSong 返回
      unawaited(Future.wait([lyricFuture, artworkFuture]));

      onSongPlayed?.call(song);
    } catch (e, st) {
      _isLoading = false;
      _isSwitching = false;
      nowPlayingHandler?.endSwitching();
      DebugLogBus.add('[PlayerController] playSong error: $e\n$st');
      state = state.copyWith(error: e.toString(), isPlaying: false);
    }
  }

  /// 取流：先查预取缓存，没有再请求后端。
  ///
  /// 返回的 url 已经过代理判定（B站/YouTube 的 Referer 校验、酷狗只有 HTTP
  /// 的那批都走 `/proxy`），调用方直接塞给引擎即可。
  Future<({String url, String quality, int bitrate, bool preview})>
  _resolveStream(Song song, String quality, {bool usePreload = true}) async {
    // mid 是「档位标识」：酷狗换音质要换 hash，QQ 要 media_mid。
    // 拿不到该档位时退到下一档，而不是让后端自己猜（那会多一次反查）。
    final plan = _resolveStreamPlan(song, quality);
    final key = _preloadKey(song, plan.quality, plan.mediaId);

    final cached = usePreload ? _takePreloaded(key) : null;
    if (cached != null) {
      DebugLogBus.add('[PlayerController] 预取命中 ${song.name}');
      return _toPlayable(song, cached);
    }

    final info = await repository.fetchStream(
      songId: song.id,
      source: song.source,
      quality: plan.quality,
      mediaId: plan.mediaId,
    );
    return _toPlayable(song, info);
  }

  /// 把取流回执转成实际播放地址（含代理转换）。
  ({String url, String quality, int bitrate, bool preview}) _toPlayable(
    Song song,
    StreamInfo info,
  ) {
    final rawUrl = info.url;
    // 这些源的直链要么需要 Referer，要么只有 HTTP（酷狗 fsvippc），
    // 都必须经后端代理播放，否则 iOS ATS 直接拦。
    final url =
        _needsProxy(song.source, rawUrl)
            ? '${AppConfig.baseUrl}/proxy?url=${Uri.encodeComponent(rawUrl)}'
            : rawUrl;
    return (
      url: url,
      quality: info.quality,
      bitrate: info.bitrate,
      preview: info.preview,
    );
  }

  String _preloadKey(Song song, String quality, String? mediaId) =>
      '${song.source}:${song.id}:$quality:${mediaId ?? ''}';

  /// 取一条预取结果：命中即删（直链有签名时效，留着下次也会 403）。
  StreamInfo? _takePreloaded(String key) {
    final entry = _preload.remove(key);
    if (entry == null) return null;
    if (DateTime.now().difference(entry.at) > _preloadTtl) return null;
    return entry.info;
  }

  /// 在 queue 里抽一个不是 [currentIndex] 的随机下标。
  int _pickRandomIndex(int length, int currentIndex) {
    if (length <= 1) return 0;
    int index;
    do {
      index = _random.nextInt(length);
    } while (index == currentIndex);
    return index;
  }

  /// 预取当前曲后面的 [_preloadAhead] 首。
  ///
  /// 为什么不是「等播完再去取」：后端要串行打上游接口（网易云/QQ/酷狗），
  /// 冷启动一趟 600ms~2s。这个时间里播放器已经 completed，用户听到的就是
  /// 上一首重播了几秒再被切走。提前把直链拿到手，切歌只剩 `setSource`。
  ///
  /// 串行 + 单首提前返回：并发打后端会把同一批次的上游请求挤在一起，
  /// 反而更慢；预取是后台行为，慢一点没有代价。
  void _preloadUpcoming({
    required List<Song> queue,
    required int currentIndex,
    required PlayMode playMode,
    required String quality,
    bool forceRefresh = false,
  }) {
    if (queue.isEmpty) return;
    // 单曲循环永远重播同一首，预取后面没有意义。
    if (playMode == PlayMode.single) return;
    // 队列变了，旧结果作废（避免「下一首」被上一批预取带偏）
    _prunePreload();

    var index = currentIndex;
    for (var step = 1; step <= _preloadAhead; step++) {
      if (playMode == PlayMode.random) {
        if (queue.length <= 1) return;
        if (step == 1) {
          // 抽签并记住，切歌时兑现这一张。
          _plannedRandomNext = _pickRandomIndex(queue.length, currentIndex);
          index = _plannedRandomNext!;
        } else {
          // 第二首只是顺带热身，抽到哪算哪。
          index = _pickRandomIndex(queue.length, currentIndex);
        }
      } else {
        index = (index + 1) % queue.length;
      }
      if (index == currentIndex) return;
      final song = queue[index];
      // 本地文件与 Jamendo 直链不需要取流
      if (song.source == 'local' ||
          (song.source == 'jamendo' && song.urlId.startsWith('http'))) {
        continue;
      }
      final plan = _resolveStreamPlan(song, quality);
      final key = _preloadKey(song, plan.quality, plan.mediaId);
      if (_preloadInFlight.contains(key)) continue;
      if (_preload.containsKey(key)) {
        // 已有一份：除非明确要求刷新，否则不动它。
        if (!forceRefresh) continue;
        _preload.remove(key);
      }

      _preloadInFlight.add(key);
      DebugLogBus.add('[PlayerController] 预取 ${song.name}');
      repository
          .fetchStream(
            songId: song.id,
            source: song.source,
            quality: plan.quality,
            mediaId: plan.mediaId,
          )
          .then((info) {
            _preload[key] = _PreloadEntry(info: info, at: DateTime.now());
            _prunePreload();
          })
          .catchError((Object e) {
            // 预取失败不影响播放：真正切过去时还会再取一次
            DebugLogBus.add('[PlayerController] 预取失败 ${song.name}: $e');
          })
          .whenComplete(() => _preloadInFlight.remove(key));
    }
  }

  /// 剩余不到 [_preloadRefreshWindow] 时，把「下一首」的预取重新取一遍。
  ///
  /// 只在这一刻补取，是有原因的：预取是在本曲**开始**时发起的（那才是它有意义
  /// 的位置——和本曲取流并行，整首歌的时间都是余量）。但直链是签名 URL，
  /// 有效期通常十几分钟；一首超长曲目或用户中途暂停很久之后，那张 URL 可能已经
  /// 失效。所以在真正需要它之前的一小段窗口里确认一次：快过期就换新的，
  /// 没过期就什么都不做（`_preloadTtl` 的一半作为新鲜度门槛）。
  void _refreshSoonExpiringPreload(Duration duration) {
    if (!state.isPlaying) return;
    if (duration <= Duration.zero) return;
    final remaining = duration - state.position;
    if (remaining > _preloadRefreshWindow) return;
    // 每首歌只补一次，避免最后 30 秒里每个 tick 都打一次后端。
    final song = state.currentSong;
    if (song == null || _refreshedForSong == '${song.source}:${song.id}') {
      return;
    }

    final queue = getQueue?.call() ?? [];
    if (queue.isEmpty) return;
    final freshAfter = _preloadTtl ~/ 2;
    // 只有「确实快要过期」才重取；刚取回来的不动。
    for (final entry in _preload.values) {
      if (DateTime.now().difference(entry.at) < freshAfter) return;
    }
    _refreshedForSong = '${song.source}:${song.id}';
    _preloadUpcoming(
      queue: queue,
      currentIndex: getCurrentQueueIndex?.call() ?? 0,
      playMode: getPlayMode?.call() ?? PlayMode.list,
      quality: getQuality?.call() ?? 'auto',
      forceRefresh: true,
    );
  }

  /// 丢掉过期条目与超出上限最旧的那批。
  void _prunePreload() {
    if (_preload.isEmpty) return;
    final now = DateTime.now();
    _preload.removeWhere((_, e) => now.difference(e.at) > _preloadTtl);
    while (_preload.length > _preloadMaxEntries) {
      String? oldestKey;
      DateTime? oldest;
      _preload.forEach((k, v) {
        if (oldest == null || v.at.isBefore(oldest!)) {
          oldest = v.at;
          oldestKey = k;
        }
      });
      if (oldestKey == null) break;
      _preload.remove(oldestKey);
    }
  }

  void _updateDurationWhenReady(Song song, String? artworkUrl) {
    // 取消上一首歌残留的轮询，防止快速切歌时 Timer 泄漏
    _durationTimer?.cancel();
    // 轮询等待 duration 可用，最多等 5 秒
    var attempts = 0;
    _durationTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      final dur = engine.duration;
      attempts++;
      if (dur != null || attempts >= 25) {
        timer.cancel();
        if (dur != null) {
          nowPlayingHandler?.setNowPlaying(
            title: song.name,
            artist: song.artist,
            artworkUrl: state.artworkUrl ?? artworkUrl,
            duration: dur,
          );
          state = state.copyWith(duration: dur);
        }
      }
    });
  }

  /// 启动时恢复上次播放的歌曲状态（仅显示，不自动播放）
  Future<void> restoreLastSong(Song song) async {
    String? artworkUrl;
    if (song.picUrl != null && song.picUrl!.isNotEmpty) {
      final encoded = Uri.encodeComponent(song.picUrl!);
      artworkUrl = '${AppConfig.baseUrl}/imgproxy?url=$encoded';
    } else if (song.picId.isNotEmpty) {
      artworkUrl = repository.buildPicProxyUrl(
        picId: song.picId,
        source: song.source,
      );
    }
    // 读取上次保存的播放进度
    final saved = await persistence.loadPlaybackPosition();
    _restoredPosition = saved.position > Duration.zero ? saved.position : null;
    state = PlayerState(
      currentSong: song,
      isPlaying: false,
      position: saved.position,
      duration: saved.duration,
      lyrics: const [],
      currentLyricIndex: -1,
      artworkUrl: artworkUrl,
      error: null,
    );
    nowPlayingHandler?.setNowPlaying(
      title: song.name,
      artist: song.artist,
      artworkUrl: artworkUrl,
    );
  }

  Future<void> toggle() async {
    final wasPlaying = state.isPlaying;
    // 引擎未加载（恢复状态后第一次播放）：加载并跳到保存的进度
    if (!wasPlaying && state.currentSong != null && engine.duration == null) {
      final quality = getQuality?.call() ?? 'auto';
      final seekTo = _restoredPosition;
      _restoredPosition = null;
      await playSong(state.currentSong!, quality: quality, seekTo: seekTo);
      return;
    }
    // 先更新状态让 UI 立即响应
    state = state.copyWith(isPlaying: !wasPlaying);
    try {
      if (wasPlaying) {
        await engine.pause();
      } else {
        await engine.play();
      }
    } catch (e) {
      // 引擎操作失败，回滚状态
      state = state.copyWith(isPlaying: wasPlaying);
    }
  }

  Future<void> pause() async {
    if (state.isPlaying) {
      await engine.pause();
      state = state.copyWith(isPlaying: false);
      // 保存当前进度和总时长，供下次启动恢复
      persistence
          .savePlaybackPosition(
            position: state.position,
            duration: state.duration,
          )
          .ignore();
    }
  }

  Future<void> seekTo(Duration position) async {
    // 先更新状态，避免 _tick() 在 seek 完成前用旧 position 覆盖导致回跳
    final index = _resolveLyricIndex(state.lyrics, position);
    state = state.copyWith(position: position, currentLyricIndex: index);
    await engine.seek(position);
  }

  /// 淡出后暂停（用于睡眠定时器到期）
  Future<void> fadeOutAndPause({
    Duration fadeDuration = const Duration(seconds: 5),
  }) async {
    if (!state.isPlaying) return;
    final steps = 20;
    final stepDuration = Duration(
      milliseconds: fadeDuration.inMilliseconds ~/ steps,
    );
    for (int i = steps - 1; i >= 0; i--) {
      if (!state.isPlaying) break;
      await engine.setVolume(i / steps);
      await Future.delayed(stepDuration);
    }
    await pause();
    await engine.setVolume(1.0); // 恢复音量
  }

  static final _random = Random();

  Future<void> skipNext({
    required List<Song> queue,
    required int currentIndex,
    required PlayMode playMode,
    required String quality,
  }) async {
    if (queue.isEmpty) return;
    int nextIndex;
    if (playMode == PlayMode.random) {
      final planned = _plannedRandomNext;
      if (queue.length <= 1) {
        nextIndex = 0;
      } else if (planned != null &&
          planned >= 0 &&
          planned < queue.length &&
          planned != currentIndex) {
        // 兑现预取时抽的那张签，直链已经在手。
        nextIndex = planned;
      } else {
        nextIndex = _pickRandomIndex(queue.length, currentIndex);
      }
      _plannedRandomNext = null;
    } else {
      nextIndex = (currentIndex + 1) % queue.length;
    }
    setCurrentQueueIndex?.call(nextIndex);
    await playSong(queue[nextIndex], quality: quality);
    // 再下一首的封面提前进图片缓存（切歌时不会空一拍）
    _precacheArtworkOf(queue, nextIndex, playMode);
  }

  /// 预热后面一两首的封面进图片缓存。
  void _precacheArtworkOf(
    List<Song> queue,
    int currentIndex,
    PlayMode playMode,
  ) {
    if (queue.length <= 1) return;
    for (var step = 1; step <= _preloadAhead; step++) {
      final index =
          playMode == PlayMode.random
              ? _random.nextInt(queue.length)
              : (currentIndex + step) % queue.length;
      if (index == currentIndex) break;
      final song = queue[index];
      String? url;
      if (song.picUrl != null && song.picUrl!.isNotEmpty) {
        url =
            '${AppConfig.baseUrl}/imgproxy?url=${Uri.encodeComponent(song.picUrl!)}';
      } else if (song.picId.isNotEmpty) {
        url = repository.buildPicProxyUrl(
          picId: song.picId,
          source: song.source,
        );
      }
      if (url != null) {
        final imageProvider = NetworkImage(url);
        imageProvider.obtainKey(ImageConfiguration.empty).then((key) {
          final cache = PaintingBinding.instance.imageCache;
          if (!cache.containsKey(key)) {
            imageProvider.resolve(ImageConfiguration.empty);
          }
        }).ignore();
      }
    }
  }

  Future<void> skipPrevious({
    required List<Song> queue,
    required int currentIndex,
    required PlayMode playMode,
    required String quality,
  }) async {
    if (queue.isEmpty) return;
    int prevIndex;
    if (playMode == PlayMode.random) {
      if (queue.length <= 1) {
        prevIndex = 0;
      } else {
        do {
          prevIndex = _random.nextInt(queue.length);
        } while (prevIndex == currentIndex);
      }
    } else {
      prevIndex = (currentIndex - 1 + queue.length) % queue.length;
    }
    setCurrentQueueIndex?.call(prevIndex);
    await playSong(queue[prevIndex], quality: quality);
  }

  Future<void> setVolume(double volume) async {
    await engine.setVolume(volume);
  }

  Future<void> setSpeed(double speed) async {
    await engine.setSpeed(speed);
    state = state.copyWith(speed: speed);
  }

  @override
  void dispose() {
    _preload.clear();
    _preloadInFlight.clear();
    _timer?.cancel();
    _durationTimer?.cancel();
    _completeSub?.cancel();
    super.dispose();
  }
}

final audioEngineProvider = Provider<AudioEngine>(
  (ref) => JustAudioEngine(sharedPlayer),
);

final playerControllerProvider =
    StateNotifierProvider<PlayerController, PlayerState>((ref) {
      final controller = PlayerController(
        repository: ref.watch(solaraRepositoryProvider),
        engine: ref.watch(audioEngineProvider),
        themeController: ref.read(themeControllerProvider.notifier),
        onSongPlayed: (song) {
          final historyNotifier = ref.read(historyStateProvider.notifier);
          historyNotifier.addEntry(song);
          ref
              .read(persistentStateProvider)
              .saveHistory(ref.read(historyStateProvider));
        },
        getQueue: () => ref.read(queueStateProvider).songs,
        getPlayMode: () => ref.read(queueStateProvider).playMode,
        getCurrentQueueIndex: () => ref.read(queueStateProvider).currentIndex,
        setCurrentQueueIndex:
            (index) =>
                ref.read(queueStateProvider.notifier).setCurrentIndex(index),
        getQuality: () => ref.read(settingsStateProvider).playbackQuality,
        persistence: ref.read(persistentStateProvider),
      );

      // 注入锁屏/灵动岛/控制中心切歌回调
      nowPlayingHandler?.onSkipNext = () async {
        final q = ref.read(queueStateProvider);
        final settings = ref.read(settingsStateProvider);
        await controller.skipNext(
          queue: q.songs,
          currentIndex: q.currentIndex,
          playMode: q.playMode,
          quality: settings.playbackQuality,
        );
      };
      nowPlayingHandler?.onSkipPrevious = () async {
        final q = ref.read(queueStateProvider);
        final settings = ref.read(settingsStateProvider);
        await controller.skipPrevious(
          queue: q.songs,
          currentIndex: q.currentIndex,
          playMode: q.playMode,
          quality: settings.playbackQuality,
        );
      };

      // 内部音量始终为1.0，跟随系统音量
      return controller;
    });

/// 覆盖 sleepTimerProvider，让到期时淡出后暂停播放器
final sleepTimerWithPlayerProvider =
    StateNotifierProvider<SleepTimerNotifier, SleepTimerState>(
      (ref) => SleepTimerNotifier(
        onExpired: () {
          final controller = ref.read(playerControllerProvider.notifier);
          controller.fadeOutAndPause();
        },
      ),
    );

/// 一条预取结果。`at` 是取回时间，用来判过期。
class _PreloadEntry {
  final StreamInfo info;
  final DateTime at;

  const _PreloadEntry({required this.info, required this.at});
}
