import 'package:dio/dio.dart';
import '../domain/models/discover.dart';
import '../domain/models/song.dart';
import '../domain/models/stream_info.dart';
import 'api/solara_api.dart';
import '../services/debug_log_bus.dart';

class AuthRequiredException implements Exception {
  @override
  String toString() => 'Auth required';
}

class SolaraRepository {
  final SolaraApi api;
  final Dio dio;

  SolaraRepository({required this.api, required this.dio});

  Uri _resolve(Uri relative) {
    return Uri.parse(dio.options.baseUrl).resolveUri(relative);
  }

  void _ensureAuthed(Response response) {
    final status = response.statusCode ?? 0;
    final location = response.headers.value('location') ?? '';
    if (status == 302 ||
        status == 401 ||
        status == 403 ||
        location.contains('/login')) {
      throw AuthRequiredException();
    }
  }

  Future<List<Song>> search({
    required String keyword,
    required String source,
    int count = 20,
    int page = 1,
  }) async {
    final uri = _resolve(
      api.buildSearchUri(
        keyword: keyword,
        source: source,
        count: count,
        page: page,
      ),
    );
    DebugLogBus.add('Search: $keyword ($source) page=$page');
    final response = await dio.getUri(uri);
    _ensureAuthed(response);
    final data = response.data;
    if (data is! List) {
      throw Exception('Invalid search response');
    }
    DebugLogBus.add('Search results: ${data.length}');
    return data
        .map((item) => Song.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  /// 取播放地址与实际音质。
  ///
  /// 返回的 StreamInfo 里带着后端实测拿到的档位/码率/格式，
  /// 调用方必须用它显示音质、决定文件后缀、判断是不是试听片段。
  Future<StreamInfo> fetchStream({
    required String songId,
    required String source,
    required String quality,
    String? mediaId,
  }) async {
    final uri = _resolve(
      api.buildSongUrlUri(
        songId: songId,
        source: source,
        quality: quality,
        mediaId: mediaId,
      ),
    );
    DebugLogBus.add(
      'Fetch stream: $songId ($source) quality=$quality mid=$mediaId',
    );
    final response = await dio.getUri(uri);
    _ensureAuthed(response);
    final data = response.data;

    // 新接口回 {url, quality, bitrate, ext, size, preview}；
    // 老的透传接口（bilibili/jamendo）仍可能只给 {url} 或裸字符串。
    if (data is Map && data['url'] != null) {
      final info = StreamInfo.fromJson(data);
      DebugLogBus.add(
        'Stream: ${info.quality} ${info.bitrate}bps ${info.ext} preview=${info.preview}',
      );
      return info;
    }
    if (data is List &&
        data.isNotEmpty &&
        data[0] is Map &&
        data[0]['url'] != null) {
      return StreamInfo.fromJson(data[0] as Map);
    }
    if (data is String && data.startsWith('http')) {
      return StreamInfo.fromUrl(data);
    }
    throw Exception('Invalid stream response: $data');
  }

  /// 只取播放地址。播放器不需要音质信息的地方用它。
  Future<String> fetchSongUrl({
    required String songId,
    required String source,
    required String quality,
    String? mediaId,
  }) async {
    final info = await fetchStream(
      songId: songId,
      source: source,
      quality: quality,
      mediaId: mediaId,
    );
    return info.url;
  }

  Future<String> fetchLyric({
    required String songId,
    required String source,
  }) async {
    final uri = _resolve(api.buildLyricUri(songId: songId, source: source));
    DebugLogBus.add('Fetch lyric: $songId');
    final response = await dio.getUri(uri);
    _ensureAuthed(response);
    return response.data.toString();
  }

  /// 直接本地计算封面代理 URL，不发网络请求
  String buildPicProxyUrl({
    required String picId,
    required String source,
    int size = 300,
  }) {
    final uri = _resolve(
      api.buildPicUri(picId: picId, source: source, size: size),
    );
    return uri.toString();
  }

  Future<String> fetchPicUrl({
    required String picId,
    required String source,
    int size = 300,
  }) async {
    final uri = _resolve(
      api.buildPicUri(picId: picId, source: source, size: size),
    );
    DebugLogBus.add('Fetch pic: $picId');
    final response = await dio.getUri(uri);
    _ensureAuthed(response);
    final data = response.data;
    if (data is Map && data['url'] != null) {
      return data['url'].toString();
    }
    return uri.toString();
  }

  Future<String> fetchMvUrl({
    required String mvId,
    required String source,
  }) async {
    final uri = _resolve(api.buildMvUrlUri(mvId: mvId, source: source));
    DebugLogBus.add('Fetch mv url: $mvId');
    final response = await dio.getUri(uri);
    _ensureAuthed(response);
    final data = response.data;
    // 支持 {url:...}, {video:...}, [{url:...}], [{video:...}] 等格式
    if (data is Map) {
      final v = data['url'] ?? data['video'];
      if (v != null) return v.toString();
    }
    if (data is List && data.isNotEmpty && data[0] is Map) {
      final v = data[0]['url'] ?? data[0]['video'];
      if (v != null) return v.toString();
    }
    if (data is String && data.startsWith('http')) return data;
    throw Exception('Invalid mv url response: \$data');
  }

  /// [onlyAvailable] 为 true 时后端会先剔掉详情页取不到歌的空榜单
  /// （「查看全部榜单」页用；首页照旧不过滤，免得首屏等探测）。
  Future<List<LeaderboardItem>> fetchLeaderboardList({
    required String source,
    bool onlyAvailable = false,
  }) async {
    final uri = _resolve(
      api.buildDiscoverLeaderboardListUri(
        source: source,
        onlyAvailable: onlyAvailable,
      ),
    );
    DebugLogBus.add('Fetch leaderboard list: $source');
    final response = await dio.getUri(uri);
    _ensureAuthed(response);
    final data = response.data;
    if (data is! List) throw Exception('Invalid leaderboard list response');
    return data
        .map(
          (e) => LeaderboardItem.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  /// 按需取某个榜单的拼图封面（前 4 首歌的专辑图）。
  ///
  /// 首页列表只为前几张卡带 coverUrls，其余卡片滚到视口时再单独要，
  /// 这样首屏不用等几十次上游调用，而每张卡最终都有图。
  Future<List<String>> fetchLeaderboardCovers({
    required String id,
    required String source,
  }) async {
    final uri = _resolve(
      Uri(
        path: '/api/discover/leaderboard/${Uri.encodeComponent(id)}/covers',
        queryParameters: {'source': source},
      ),
    );
    final response = await dio.getUri(uri);
    _ensureAuthed(response);
    final data = response.data;
    if (data is! Map) return const [];
    final raw = data['coverUrls'];
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<List<SongListItem>> fetchSongList({
    required String source,
    String sort = 'hot',
    String tag = '',
    int page = 1,
    int limit = 30,
  }) async {
    final uri = _resolve(
      api.buildDiscoverSongListUri(
        source: source,
        sort: sort,
        tag: tag,
        page: page,
        limit: limit,
      ),
    );
    DebugLogBus.add('Fetch song list: $source sort=$sort');
    final response = await dio.getUri(uri);
    _ensureAuthed(response);
    final data = response.data;
    if (data is! List) throw Exception('Invalid song list response');
    return data
        .map((e) => SongListItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<Song>> fetchLeaderboardDetail({
    required String id,
    required String source,
    int page = 1,
    int limit = 30,
  }) async {
    final uri = _resolve(
      api.buildDiscoverLeaderboardDetailUri(
        id: id,
        source: source,
        page: page,
        limit: limit,
      ),
    );
    DebugLogBus.add('Fetch leaderboard detail: $id ($source)');
    final response = await dio.getUri(uri);
    _ensureAuthed(response);
    final data = response.data;
    if (data is! List) throw Exception('Invalid leaderboard detail response');
    return data
        .map((e) => Song.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<Song>> fetchSongListDetail({
    required String id,
    required String source,
    int page = 1,
    int limit = 30,
  }) async {
    final uri = _resolve(
      api.buildDiscoverSongListDetailUri(
        id: id,
        source: source,
        page: page,
        limit: limit,
      ),
    );
    DebugLogBus.add('Fetch song list detail: $id ($source)');
    final response = await dio.getUri(uri);
    _ensureAuthed(response);
    final data = response.data;
    if (data is! List) throw Exception('Invalid song list detail response');
    return data
        .map((e) => Song.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
