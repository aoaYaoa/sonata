import '../../domain/models/song.dart';

/// 音质档位的单一事实来源。
///
/// 之前播放页和设置页各写了一份档位表：设置页固定列 4 档，
/// 播放页按 `song.altIds` 过滤。结果是同一个设置在两个入口能选到的东西不一样——
/// 在设置里挑「无损 FLAC」，QQ 匿名态根本拿不到这一档，用户白等一次失败，
/// 而播放页里那一档压根不显示。现在两处都走这里。
class PlaybackQuality {
  /// 依次从低到高的实际档位；`auto` 单独处理（让各音源给自身上限）。
  static const tiers = <String>['128', '320', 'flac'];

  /// 选中 `auto` 时该音源最高能到哪里，用于在设置里说明。
  static String label(String q) {
    switch (q) {
      case 'auto':
        return '自动（最高可用）';
      case '128':
        return '标准 128kbps';
      case '320':
        return '高品质 320kbps';
      case 'flac':
      case 'FLAC':
        return '无损 FLAC';
      default:
        return q;
    }
  }

  /// 短标签，播放页小格子里用。
  static String badge(String q) {
    switch (q) {
      case 'flac':
      case 'FLAC':
        return 'FLAC';
      case '128':
      case '320':
        return '${q}K';
      default:
        return q;
    }
  }

  /// 当前歌曲真正能拿到的档位，`auto` 永远在最前。
  ///
  /// 只有酷狗 / QQ 的 `altIds` 是「确实存在且当前账号有权限」的白名单，
  /// 其它音源不带这张表、会按 br 自动降级，所以对它们照常列全部档。
  static List<String> availableFor(Song? song) {
    final alt = song?.altIds ?? const <String, String>{};
    final strict = song?.source == 'kugou' || song?.source == 'tencent';
    return [
      'auto',
      for (final tier in tiers)
        if (!strict || alt.containsKey(tier)) tier,
    ];
  }
}
