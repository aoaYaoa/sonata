/// 音源的单一事实来源。
///
/// 之前 5 个页面各写了一份 switch 来把 `netease` 翻成「网易云」，
/// 设置页还单独维护了一份「可选音源」列表——结果是：`AppConfig.sources`
/// 有 6 个音源（含 B站 / YouTube / Jamendo），设置页却只列 4 个，
/// 用户在设置里根本切不到后三个；反过来设置页里能选的「酷我」又不在
/// `AppConfig.sources` 里，选了也搜不出东西。
///
/// 现在 label 与可选列表都从这里出，改一处就够。
class MusicSource {
  final String id;

  /// 短名，胶囊/角标用：「网易云」「QQ」。
  final String short;

  /// 全名，设置页与歌曲信息用：「网易云音乐」「QQ 音乐」。
  final String full;

  const MusicSource(this.id, this.short, this.full);

  static const all = <MusicSource>[
    MusicSource('netease', '网易云', '网易云音乐'),
    MusicSource('tencent', 'QQ', 'QQ 音乐'),
    MusicSource('kugou', '酷狗', '酷狗音乐'),
    MusicSource('bilibili', 'B站', '哔哩哔哩'),
    MusicSource('youtube', 'YouTube', 'YouTube'),
    MusicSource('jamendo', 'Jamendo', 'Jamendo'),
  ];

  /// 可以拿来做「搜索 / 发现 / 榜单」的音源，顺序即选择面板里的顺序。
  static List<String> get ids => all.map((s) => s.id).toList();

  static MusicSource? byId(String id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    // 本地歌曲不走网络音源，但它会出现在「歌曲信息」里
    if (id == 'local') return const MusicSource('local', '本地', '本地文件');
    return null;
  }

  static String shortLabel(String id) => byId(id)?.short ?? id;

  static String fullLabel(String id) => byId(id)?.full ?? id;
}
