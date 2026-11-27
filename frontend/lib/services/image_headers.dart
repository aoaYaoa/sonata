import 'app_config.dart';

/// 把 CDN 图片地址改写成走后端 imgproxy。
///
/// 需要代理的原因分三类：
///  1. 图床校验 Referer（网易云、B站），直连会被 403；
///  2. 地址是 http，iOS ATS 直接拦（腾讯 y.gtimg.cn 常给 http）；
///  3. 域名在境内被墙（ytimg.com / jamendo.com），手机侧直连取不到图。
/// 加进来的 host 必须同步到后端 IMG_PROXY_ALLOWED_HOSTS，否则 imgproxy 回 400。
String proxyImageUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  final host = uri.host;
  if (host.endsWith('.music.126.net') ||
      host.endsWith('.163.com') ||
      host.endsWith('.qq.com') ||
      host.endsWith('.gtimg.cn') ||
      host.endsWith('.kugou.com') ||
      host.endsWith('.hdslb.com') ||
      host.endsWith('.ytimg.com') ||
      host.endsWith('.jamendo.com')) {
    return '${AppConfig.baseUrl}/imgproxy?url=${Uri.encodeComponent(url)}';
  }
  return url;
}

/// 把榜单/歌单封面地址换成指定尺寸再代理。
///
/// 各家图床的尺寸参数写法不同，必须按 host 分别处理：
///   - 网易云：`?param=400y400`（不加时返回原图，动辄几百 KB）
///   - 酷狗：路径里的 `/240/` 段就是尺寸，替换该段
///   - 腾讯：文件名里的 `R500x500` 是尺寸，但只有 150/300/500 三档存在，
///     请求别的尺寸会 404，所以必须就近吸附到这三档
///   - B站：后缀 `@320w_320h_1c.webp`，比原图小两个数量级
///   - Jamendo：`width=` 查询参数
/// 认不出的 host 原样返回，让 CDN 自己决定。
String sizedCoverUrl(String url, {int size = 400}) {
  if (url.isEmpty) return url;
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  final host = uri.host;

  String out = url;
  if (host.endsWith('.music.126.net') || host.endsWith('.163.com')) {
    out = uri.replace(queryParameters: {'param': '${size}y$size'}).toString();
  } else if (host.endsWith('.kugou.com')) {
    // 酷狗封面形如 https://imge.kugou.com/mcommon/240/2024.../x.png
    out = url.replaceFirst(
      RegExp(r'/(?:mcommon|stdmusic)/\d+/'),
      '/mcommon/$size/',
    );
  } else if (host.endsWith('.gtimg.cn')) {
    // 腾讯图床只提供 150/300/500 三种规格，其余尺寸一律 404
    final snapped = size >= 500 ? 500 : (size >= 300 ? 300 : 150);
    out = url.replaceFirst(RegExp(r'R\d+x\d+'), 'R${snapped}x$snapped');
  } else if (host.endsWith('.hdslb.com')) {
    // B站图床用后缀缩放，加 `@320w_320h_1c.webp` 比原图小两个数量级
    // （实测 281KB → 8.6KB）。webp 由 Flutter 解码，iOS 原生支持。
    final snapped = size <= 240 ? 240 : (size <= 320 ? 320 : 480);
    out = '$url@${snapped}w_${snapped}h_1c.webp';
  } else if (host.endsWith('.jamendo.com')) {
    // Jamendo 封面形如 https://usercontent.jamendo.com?type=album&id=..&width=300
    // 电台图是静态文件名 ...bestof150.jpg，没有尺寸参数可改，交给 CDN。
    if (uri.queryParameters.containsKey('width')) {
      final q = Map<String, String>.from(uri.queryParameters)
        ..['width'] = '$size';
      out = uri.replace(queryParameters: q).toString();
    }
  }
  return proxyImageUrl(out);
}
