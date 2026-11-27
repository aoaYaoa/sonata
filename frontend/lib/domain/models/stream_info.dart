/// 取流回执。
///
/// 后端各音源能给的档位不一致（酷狗能给无损、QQ 匿名态只有 128k），
/// 所以「用户选了 320」不等于「拿到的是 320」。这里带着后端实测的实际值，
/// UI 显示它，而不是显示用户点的那个数字。
class StreamInfo {
  final String url;

  /// 实际拿到的档位：'128' / '320' / 'flac'。
  final String quality;

  /// 实际码率，单位 bps。未知为 0。
  final int bitrate;

  /// 文件格式：mp3 / m4a / flac。
  final String ext;

  /// 文件字节数，未知为 0。
  final int size;

  /// true 表示这是试听片段（QQ 无权限时回落到 60 秒试听）。
  final bool preview;

  const StreamInfo({
    required this.url,
    this.quality = '',
    this.bitrate = 0,
    this.ext = '',
    this.size = 0,
    this.preview = false,
  });

  /// 兼容老接口：只给了 url 字符串时，音质未知。
  factory StreamInfo.fromUrl(String url) => StreamInfo(url: url);

  static StreamInfo fromJson(Map data) {
    return StreamInfo(
      url: data['url']?.toString() ?? '',
      quality: data['quality']?.toString() ?? '',
      bitrate: _toInt(data['bitrate']),
      ext: data['ext']?.toString() ?? '',
      size: _toInt(data['size']),
      preview: data['preview'] == true,
    );
  }

  /// 用于下载文件名后缀。后端没给 ext 时按码率猜。
  String get fileExtension {
    if (ext.isNotEmpty) return ext;
    if (quality == 'flac') return 'flac';
    return 'mp3';
  }

  static int _toInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
