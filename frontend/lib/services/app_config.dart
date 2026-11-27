import '../../domain/models/music_source.dart';

class AppConfig {
  static const String baseUrl = 'https://solara.uonoe.com';

  /// 与 pubspec.yaml 的 version 保持一致。不引 package_info_plus：
  /// 只为了在设置页显示一行版本号而多一个原生插件不值得。
  static const String version = '1.0.0';
  static const String buildNumber = '1';

  /// 可搜索的音源。
  ///
  /// 顺序与「音源选择」面板一致，定义在 [MusicSource] 里——设置页此前
  /// 单独维护了一份只有 4 个的列表，导致 B站 / YouTube / Jamendo 在搜索页
  /// 能选、在设置页选不到；反过来设置页里的「酷我」并不在支持列表里。
  static List<String> get sources => MusicSource.ids;

  static const List<String> genres = [
    '流行',
    '摇滚',
    '古典',
    '民谣',
    '电子',
    '爵士',
    '说唱',
    '乡村',
    '蓝调',
    'R&B',
    '金属',
    '嘻哈',
    '轻音乐',
  ];
}
