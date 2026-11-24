import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'app/app.dart';
import 'services/audio_handler.dart';

/// 媒体会话处理器（锁屏/通知栏/控制中心）。
///
/// 可空：只有走完 [main] 的完整启动流程后才有值。
/// 单元测试、以及任何在 AudioService.init 之前就被构造的场景
/// （历史上 player_controller_test 直接拿到 LateInitializationError）
/// 在这里读到 null，调用方需用 `?.` 跳过锁屏更新。
SolaraAudioHandler? nowPlayingHandler;

AudioPlayer? _sharedPlayer;

/// 全局共享的播放器实例。
///
/// 惰性创建：正常启动时由 [main] 注入带均衡器管线的实例；
/// 单元测试或任何未走 [main] 的场景（如 widget test 直接 pump SolaraApp）
/// 回退到默认实例，而不是抛 LateInitializationError。
AudioPlayer get sharedPlayer => _sharedPlayer ??= AudioPlayer();

set sharedPlayer(AudioPlayer player) => _sharedPlayer = player;
AndroidEqualizer? sharedEqualizer;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 捕获 Flutter 框架错误（如 build 阶段异常），防止 release 模式直接崩溃
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[FlutterError] ${details.exceptionAsString()}');
  };

  // 捕获所有未处理的异步异常
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[Unhandled] $error\n$stack');
    return true; // 已处理，不再传播到引擎层
  };

  AndroidEqualizer? androidEq;
  if (Platform.isAndroid) {
    androidEq = AndroidEqualizer();
    sharedEqualizer = androidEq;
  }

  // 限制图片缓存，防止 iOS 内存压力导致闪退
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024; // 50MB
  PaintingBinding.instance.imageCache.maximumSize = 200; // 最多 200 张

  sharedPlayer = AudioPlayer(
    audioPipeline: androidEq != null
        ? AudioPipeline(androidAudioEffects: [androidEq])
        : null,
  );

  final handler = await AudioService.init(
    builder: () => SolaraAudioHandler(sharedPlayer),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.uonoe.solara.audio',
      androidNotificationChannelName: 'Solara',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      // macOS 媒体控制支持
      preloadArtwork: true,
      artDownscaleWidth: 512,
      artDownscaleHeight: 512,
      fastForwardInterval: const Duration(seconds: 10),
      rewindInterval: const Duration(seconds: 10),
    ),
  ).timeout(
    // 某些平台（Linux/Windows 桌面、测试环境）没有媒体会话桥接，
    // AudioService.init 可能长时间不返回；超时后退化为"无锁屏控制"，
    // 应用主体仍可正常播放。
    const Duration(seconds: 10),
    onTimeout: () {
      debugPrint('[main] AudioService.init 超时，跳过锁屏控制');
      return SolaraAudioHandler(sharedPlayer);
    },
  );
  nowPlayingHandler = handler;

  runApp(const ProviderScope(child: SolaraApp()));
}
