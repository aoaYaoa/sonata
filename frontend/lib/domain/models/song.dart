class Song {
  final String id;
  final String name;
  final String artist;
  final String album;
  final String picId;
  final String urlId;
  final String lyricId;
  final String source;
  final String? picUrl; // 直接图片URL（来自发现页，避免pic_id精度损失）
  final String? mvId; // MV ID（存在时可播放MV）

  /// 取流时用的第二个标识。
  ///
  /// QQ 音乐必填：filename 的中段是 media_mid，与 songmid 不同，
  /// 用错会拿到 result=101404。其它音源留空。
  final String? mediaId;

  /// 各音质档位的独立标识（hash / media_mid）。
  ///
  /// 酷狗的音质由 hash 决定，br 参数无效，所以换档必须换这个值。
  /// 键是音质标识（'128' / '320' / 'flac'），值是该档位的 hash。
  /// 只包含「确实存在且当前账号有权限」的档位——不在表里就是拿不到。
  final Map<String, String> altIds;

  const Song({
    required this.id,
    required this.name,
    required this.artist,
    required this.album,
    required this.picId,
    required this.urlId,
    required this.lyricId,
    required this.source,
    this.picUrl,
    this.mvId,
    this.mediaId,
    this.altIds = const {},
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      artist: json['artist']?.toString() ?? '',
      album: json['album']?.toString() ?? '',
      picId: json['pic_id']?.toString() ?? '',
      urlId: json['url_id']?.toString() ?? '',
      lyricId: json['lyric_id']?.toString() ?? '',
      source: json['source']?.toString() ?? 'netease',
      picUrl: json['pic_url']?.toString(),
      mvId: json['mv_id']?.toString(),
      mediaId: _emptyToNull(json['media_id']),
      altIds: _parseAltIds(json['alt_ids']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'artist': artist,
      'album': album,
      'pic_id': picId,
      'url_id': urlId,
      'lyric_id': lyricId,
      'source': source,
      if (picUrl != null) 'pic_url': picUrl,
      if (mvId != null) 'mv_id': mvId,
      if (mediaId != null) 'media_id': mediaId,
      if (altIds.isNotEmpty) 'alt_ids': altIds,
    };
  }

  /// 取指定档位的标识。没有该档位时返回 null，调用方据此决定降级到哪一档。
  String? altIdFor(String quality) => altIds[quality];

  static String? _emptyToNull(Object? v) {
    final s = v?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }

  static Map<String, String> _parseAltIds(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((key, value) {
      final v = value?.toString() ?? '';
      if (v.isNotEmpty) out[key.toString()] = v;
    });
    return out;
  }
}
