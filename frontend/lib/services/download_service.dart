import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import '../domain/models/song.dart';
import '../data/solara_repository.dart';
import 'app_config.dart';

class DownloadService {
  final SolaraRepository repository;
  final Dio dio;

  DownloadService({required this.repository, required this.dio});

  Future<String?> downloadSong({
    required Song song,
    required String quality,
  }) async {
    // 按歌曲实际可用的档位取流，拿到的 ext 决定后缀 ——
    // 酷狗无损是真 flac、QQ 免费曲是 m4a，一律写 .mp3 会存成打不开的文件。
    final info = await repository.fetchStream(
      songId: song.id,
      source: song.source,
      quality: quality,
      mediaId: song.altIds[quality] ?? song.mediaId,
    );

    final downloadUrl =
        _needsProxy(song.source, info.url)
            ? '${AppConfig.baseUrl}/proxy?url=${Uri.encodeComponent(info.url)}'
            : info.url;

    final qualitySuffix = info.quality.isEmpty ? quality : info.quality;
    final suggestedName =
        '${song.name}-${song.artist}-$qualitySuffix.${info.fileExtension}';
    final location = await getSaveLocation(suggestedName: suggestedName);

    String? savePath = location?.path;
    if (savePath == null) {
      final dir = await getApplicationDocumentsDirectory();
      savePath = '${dir.path}/$suggestedName';
    }

    await dio.download(downloadUrl, savePath);
    return savePath;
  }

  /// 与播放器一致：需要 Referer 或只有 HTTP 的直链都走后端代理。
  static bool _needsProxy(String source, String url) {
    if (!url.startsWith('http')) return false;
    if (source == 'bilibili' || source == 'youtube') return true;
    if (source == 'kugou' && url.startsWith('http://')) return true;
    return false;
  }
}
