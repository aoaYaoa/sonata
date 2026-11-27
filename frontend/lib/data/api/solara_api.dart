import 'api_client.dart';

class SolaraApi {
  final ApiClient client;

  SolaraApi({required this.client});

  // 说明：这里曾有一个 _signature() 往查询串塞 `s=<时间戳>`，但后端从未读取
  // 该参数（真正的签名校验是 X-Signature/X-Timestamp 头 + HMAC-SHA256，
  // 由 ENABLE_SIGNATURE 控制），属于纯误导，已删除。
  Uri _buildProxyUri(Map<String, String> params) {
    return Uri(path: '/proxy', queryParameters: params);
  }

  Uri buildSearchUri({
    required String keyword,
    required String source,
    required int count,
    required int page,
  }) {
    return _buildProxyUri({
      'types': 'search',
      'source': source,
      'name': keyword,
      'count': count.toString(),
      'pages': page.toString(),
    });
  }

  Uri buildSongUrlUri({
    required String songId,
    required String source,
    required String quality,
    String? mediaId,
  }) {
    final params = <String, String>{
      'types': 'url',
      'id': songId,
      'source': source,
      'br': quality,
    };
    // mid 是「档位标识」：酷狗换档要换 hash，QQ 要 media_mid，都从这里传。
    // 不传时后端会自己按 id 反查，多一次上游往返。
    if (mediaId != null && mediaId.isNotEmpty) {
      params['mid'] = mediaId;
    }
    return _buildProxyUri(params);
  }

  Uri buildLyricUri({required String songId, required String source}) {
    return _buildProxyUri({'types': 'lyric', 'id': songId, 'source': source});
  }

  Uri buildPicUri({
    required String picId,
    required String source,
    int size = 300,
  }) {
    return _buildProxyUri({
      'types': 'pic',
      'id': picId,
      'source': source,
      'size': size.toString(),
    });
  }

  Uri buildPlaylistUri({
    required String playlistId,
    int limit = 50,
    int offset = 0,
  }) {
    return _buildProxyUri({
      'types': 'playlist',
      'id': playlistId,
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
  }

  Uri buildMvUrlUri({required String mvId, required String source}) {
    return _buildProxyUri({'types': 'mv', 'id': mvId, 'source': source});
  }

  Uri buildDiscoverLeaderboardListUri({
    required String source,
    bool onlyAvailable = false,
  }) {
    return Uri(
      path: '/api/discover/leaderboard',
      queryParameters: {'source': source, if (onlyAvailable) 'available': '1'},
    );
  }

  Uri buildDiscoverLeaderboardDetailUri({
    required String id,
    required String source,
    int page = 1,
    int limit = 30,
  }) {
    return Uri(
      path: '/api/discover/leaderboard/$id',
      queryParameters: {
        'source': source,
        'page': page.toString(),
        'limit': limit.toString(),
      },
    );
  }

  Uri buildDiscoverSongListUri({
    required String source,
    String sort = 'hot',
    String tag = '',
    int page = 1,
    int limit = 30,
  }) {
    final params = <String, String>{
      'source': source,
      'sort': sort,
      'page': page.toString(),
      'limit': limit.toString(),
    };
    if (tag.isNotEmpty) params['tag'] = tag;
    return Uri(path: '/api/discover/songlist', queryParameters: params);
  }

  Uri buildDiscoverSongListDetailUri({
    required String id,
    required String source,
    int page = 1,
    int limit = 30,
  }) {
    return Uri(
      path: '/api/discover/songlist/$id',
      queryParameters: {
        'source': source,
        'page': page.toString(),
        'limit': limit.toString(),
      },
    );
  }
}
