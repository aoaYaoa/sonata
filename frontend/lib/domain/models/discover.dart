/// 发现页数据模型。
library;

// 排行榜榜单信息
class LeaderboardItem {
  final String id;
  final String name;
  final String? coverUrl;
  final String? updateFrequency;
  final String source;

  /// 榜单前几首歌的专辑封面，用来拼 2x2 缩略图。
  /// 榜单自带的 coverUrl 往往是「纯色底 + 榜名文字」的品牌图，
  /// 直接铺满卡片看起来仍是一堆字，所以优先用这批真封面。
  final List<String> coverUrls;

  const LeaderboardItem({
    required this.id,
    required this.name,
    this.coverUrl,
    this.updateFrequency,
    required this.source,
    this.coverUrls = const [],
  });

  factory LeaderboardItem.fromJson(Map<String, dynamic> json) {
    final urls = <String>[];
    final raw = json['coverUrls'];
    if (raw is List) {
      for (final u in raw) {
        final s = u?.toString() ?? '';
        if (s.isNotEmpty) urls.add(s);
      }
    }
    return LeaderboardItem(
      id: json['id']?.toString() ?? json['bangId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      coverUrl: json['coverUrl']?.toString() ?? json['cover']?.toString(),
      updateFrequency: json['updateFrequency']?.toString(),
      source: json['source']?.toString() ?? 'kw',
      coverUrls: urls,
    );
  }
}

// 歌单信息
class SongListItem {
  final String id;
  final String name;
  final String author;
  final String? coverUrl;
  final String? playCount;
  final String? description;
  final String source;

  /// 前几首歌的专辑封面，用于拼 2x2 缩略图。
  /// 网易云的歌单封面本来就是真图；QQ/酷狗的歌单其实是榜单，
  /// 自带封面是「纯色底 + 榜名」的品牌图，只有拼图才像一张图。
  final List<String> coverUrls;

  const SongListItem({
    required this.id,
    required this.name,
    required this.author,
    this.coverUrl,
    this.playCount,
    this.description,
    required this.source,
    this.coverUrls = const [],
  });

  factory SongListItem.fromJson(Map<String, dynamic> json) {
    final urls = <String>[];
    final raw = json['coverUrls'];
    if (raw is List) {
      for (final u in raw) {
        final s = u?.toString() ?? '';
        if (s.isNotEmpty) urls.add(s);
      }
    }
    return SongListItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      author: json['author']?.toString() ?? json['creator']?.toString() ?? '',
      coverUrl:
          json['coverUrl']?.toString() ??
          json['cover']?.toString() ??
          json['pic']?.toString(),
      playCount:
          json['playCount']?.toString() ?? json['play_count']?.toString(),
      description: json['description']?.toString() ?? json['desc']?.toString(),
      source: json['source']?.toString() ?? 'kw',
      coverUrls: urls,
    );
  }
}
