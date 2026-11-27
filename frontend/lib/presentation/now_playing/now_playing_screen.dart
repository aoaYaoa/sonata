import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/state/queue_state.dart';
import '../../domain/state/settings_state.dart';
import '../../services/image_headers.dart' show proxyImageUrl;
import '../../domain/state/favorites_state.dart';
import '../../domain/models/lyric_line.dart';
import '../../domain/models/song.dart';
import '../../services/player_controller.dart';
import '../../services/eq_service.dart';
import '../../services/sleep_timer_service.dart';
import '../../services/theme_controller.dart';
import '../../app/theme.dart';
import '../widgets/brand_placeholder.dart';
import 'now_playing_sheets.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen>
    with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;
  final ScrollController _lyricsScrollController = ScrollController();
  late PageController _pageController;
  int _currentPage = 0;
  int _lastLyricIndex = -1;
  bool _isDragging = false;
  double _dragValue = 0.0;
  double? _lyricVerticalPadding;

  /// 最后一次手动滚歌词的时间，拿来判断要不要让自动跟随先让位。
  DateTime? _lyricTouchAt;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    );
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
    _pageController = PageController();
    _pageController.addListener(() {
      final page = _pageController.page?.round() ?? 0;
      if (page != _currentPage) {
        setState(() => _currentPage = page);
      }
    });

    // 歌词滚动副作用移出 build，用 listen 单独监听
    ref.listenManual(
      playerControllerProvider.select((s) => s.currentLyricIndex),
      (_, index) {
        if (_currentPage != 1 || index < 0) return;
        if (index == _lastLyricIndex) return;
        _lastLyricIndex = index;
        final total = ref.read(playerControllerProvider).lyrics.length;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToLyric(index, total);
        });
      },
    );
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _scaleController.dispose();
    _lyricsScrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _syncPlayState(bool isPlaying) {
    if (isPlaying) {
      _rotationController.repeat();
      _scaleController.forward();
    } else {
      _rotationController.stop();
      _scaleController.reverse();
    }
  }

  void _scrollToLyric(int index, int total) {
    if (!_lyricsScrollController.hasClients || index < 0) return;
    // 用户正在手动翻歌词时不抢滚动位置：自动跟随会把人刚拖过来的那句弹走。
    // 松手 4 秒后恢复跟随。
    if (_lyricTouchAt != null &&
        DateTime.now().difference(_lyricTouchAt!).inSeconds < 4) {
      return;
    }
    const itemHeight = 44.0;
    final viewportHeight = _lyricsScrollController.position.viewportDimension;
    final targetOffset =
        (index * itemHeight) - (viewportHeight / 2) + (itemHeight / 2);
    _lyricsScrollController.animateTo(
      targetOffset.clamp(0.0, _lyricsScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // 用 select 精细订阅，避免 position/lyricIndex 每 500ms 触发整页 rebuild
    final song = ref.watch(
      playerControllerProvider.select((s) => s.currentSong),
    );
    final position = ref.watch(
      playerControllerProvider.select((s) => s.position),
    );
    final duration =
        ref.watch(playerControllerProvider.select((s) => s.duration)) ??
        Duration.zero;
    final lyrics = ref.watch(playerControllerProvider.select((s) => s.lyrics));
    final lyricIndex = ref.watch(
      playerControllerProvider.select((s) => s.currentLyricIndex),
    );
    final isPlaying = ref.watch(
      playerControllerProvider.select((s) => s.isPlaying),
    );
    final artworkUrl = ref.watch(
      playerControllerProvider.select((s) => s.artworkUrl),
    );
    final actualQuality = ref.watch(
      playerControllerProvider.select((s) => s.actualQuality),
    );
    final isPreview = ref.watch(
      playerControllerProvider.select((s) => s.isPreview),
    );
    final controller = ref.read(playerControllerProvider.notifier);
    final queueState = ref.watch(queueStateProvider);
    final queueNotifier = ref.read(queueStateProvider.notifier);
    final settings = ref.watch(settingsStateProvider);
    final favorites = ref.read(favoritesStateProvider.notifier);

    final playMode = queueState.playMode;

    _syncPlayState(isPlaying);

    // 背景取当前封面主色（themeController 已在切歌时算好）：
    // 一首歌的封面是什么色，整屏就是什么色的雾气——这是 Spotify / Apple Music
    // 的招牌手感，也让「正在播放」和「列表」在视觉上彻底分开。
    final accent = SolaraColors.vivid(
      ref.watch(themeControllerProvider).seedColor,
    );
    final primaryColor = accent;
    const bgColorDark = Color(0xFF08080C);

    return Scaffold(
      body: Container(
        color: bgColorDark,
        child: Stack(
          children: [
            // 光雾分两层：一层居中在唱片位置的大范围径向光（让封面「照亮」整屏），
            // 一层底部压黑（把控制区埋进暗处，视线自然落在封面上）。
            // 单纯把主色 55% 混进黑底会得到一片发灰的棕色，像蒙了层土；
            // 径向光+暗底才有 Spotify 那种「光在暗房里」的通透感。
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.35),
                    radius: 0.95,
                    colors: [
                      accent.withValues(alpha: 0.62),
                      accent.withValues(alpha: 0.20),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.42, 0.78],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.30),
                      Colors.black.withValues(alpha: 0.80),
                    ],
                    stops: const [0.30, 0.62, 1.0],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _buildTopBar(song, favorites, context),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: PageView(
                            controller: _pageController,
                            children: [
                              _buildVinylDiscPage(artworkUrl, primaryColor),
                              _buildLyricsPage(lyrics, lyricIndex, controller),
                            ],
                          ),
                        ),
                        _buildPageIndicator(),
                      ],
                    ),
                  ),
                  _buildToolGrid(
                    song,
                    primaryColor,
                    settings,
                    ref.read(settingsStateProvider.notifier),
                    controller,
                    actualQuality,
                    isPreview,
                  ),
                  _buildProgressBar(position, duration, controller),
                  _buildMainControls(
                    isPlaying: isPlaying,
                    controller: controller,
                    queueState: queueState,
                    queueNotifier: queueNotifier,
                    playMode: playMode,
                    settings: settings,
                    primaryColor: primaryColor,
                    bgColorDark: bgColorDark,
                    context: context,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 音质角标文本：优先用后端回报的实际档位；拿不到时显示「音质」而不是
  /// 「--」——格子里只有符号没有字，用户看不出这颗是干什么的。
  /// 试听片段加「试听」标记。
  String _actualBadge(String actualQuality, bool isPreview) {
    if (actualQuality.isEmpty) return '音质';
    final base = actualQuality == 'flac' ? 'FLAC' : '${actualQuality}K';
    return isPreview ? '$base 试听' : base;
  }

  // ── 顶栏 ───────────────────────────────────────────
  Widget _buildTopBar(
    Song? song,
    FavoritesStateNotifier favorites,
    BuildContext context,
  ) {
    final isFav = song != null && favorites.isFavorite(song);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 8, 6),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white.withValues(alpha: 0.8),
              size: 30,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  song?.name ?? '未在播放',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                if (song != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    song.artist,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
          // 收藏挪到标题旁边（QQ 音乐 / 网易云的位置）：
          // 它是「对这首歌」的操作，和音量、倍速这类播放器设置不是一回事，
          // 混在底部那排工具里会让人找不到。
          IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              transitionBuilder:
                  (child, anim) => ScaleTransition(scale: anim, child: child),
              child: Icon(
                isFav ? Icons.favorite : Icons.favorite_border,
                key: ValueKey(isFav),
                color:
                    isFav
                        ? const Color(0xFFFF5E7E)
                        : Colors.white.withValues(alpha: 0.75),
                size: 22,
              ),
            ),
            onPressed:
                song != null
                    ? () {
                      HapticFeedback.lightImpact();
                      favorites.toggleFavorite(song);
                    }
                    : null,
          ),
          // 队列入口在底部控制栏右侧（那里是它的常规位置）。
          // 顶栏原来也放了一颗，同一个动作在一屏里出现两次，看着像没对齐的重复。
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ── 唱片页 ──────────────────────────────────────────
  //
  // 除了封面本身，还叠了三层：
  //  1. 封面同色的大范围柔光（让唱片「发光」，而不是贴一张圆图）；
  //  2. 一圈 1.5pt 的半透明白环（模拟黑胶外缘）；
  //  3. 底部一颗小圆点（唱片旋转时的视觉锚点，看得出真的在转）。
  Widget _buildVinylDiscPage(String? artworkUrl, Color primaryColor) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availH = constraints.maxHeight;
        final availW = constraints.maxWidth;
        // 唱片尽量吃满可用宽度：留太多空白会让整页显得空荡、像图片没加载完。
        final discSize = math.min(360.0, math.min(availW * 0.84, availH - 16));
        return Center(
          child: SizedBox(
            width: discSize * 1.34,
            height: discSize * 1.34,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 柔光
                Container(
                  width: discSize * 1.32,
                  height: discSize * 1.32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        primaryColor.withValues(alpha: 0.40),
                        primaryColor.withValues(alpha: 0.0),
                      ],
                      stops: const [0.5, 1.0],
                    ),
                  ),
                ),
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: AnimatedBuilder(
                    animation: _rotationController,
                    builder:
                        (context, child) => Transform.rotate(
                          angle: _rotationController.value * 2 * math.pi,
                          child: child,
                        ),
                    child: Container(
                      width: discSize,
                      height: discSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.10),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 26,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child:
                            (artworkUrl ?? '').isNotEmpty
                                ? Image.network(
                                  proxyImageUrl(artworkUrl!),
                                  fit: BoxFit.cover,
                                  cacheWidth: 640,
                                  gaplessPlayback: true,
                                  errorBuilder: (_, __, ___) => _defaultCover(),
                                )
                                : _defaultCover(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── 歌词页 ──────────────────────────────────────────
  Widget _buildLyricsPage(
    List<LyricLine> lyrics,
    int lyricIndex,
    PlayerController controller,
  ) {
    if (lyrics.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        ),
      );
    }
    // 用 NotificationListener 记录手动滚动，不用 onTap 兜：
    // 手指一碰列表就算「用户接管」，不用等真的滚出偏移量。
    return NotificationListener<ScrollStartNotification>(
      onNotification: (n) {
        if (n.dragDetails != null) _lyricTouchAt = DateTime.now();
        return false;
      },
      child: ListView.builder(
        controller: _lyricsScrollController,
        itemCount: lyrics.length,
        itemExtent: 44,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(
          vertical:
              _lyricVerticalPadding ??=
                  MediaQuery.of(context).size.height * 0.1,
        ),
        itemBuilder: (context, index) {
          final line = lyrics[index];
          final isCurrent = index == lyricIndex;
          final isNear = (index - lyricIndex).abs() <= 1;
          return GestureDetector(
            onTap: () => controller.seekTo(line.time),
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: TextStyle(
                  color:
                      isCurrent
                          ? Colors.white
                          : isNear
                          ? Colors.white.withValues(alpha: 0.5)
                          : Colors.white.withValues(alpha: 0.25),
                  fontSize: isCurrent ? 17 : 14,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                ),
                child: Text(
                  line.text,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── 页面指示器 ──────────────────────────────────────
  //
  // 原来是两个小圆点：一个长一点一个短一点，谁也不知道第二条是歌词页——
  // 很多人用了几天都不知道可以往左滑。这里改成带字的双段控件，
  // 点一下也能切，把「这一页还有第二屏」直接写出来。
  Widget _buildPageIndicator() {
    const labels = ['封面', '歌词'];
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(2, (index) {
          final active = _currentPage == index;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap:
                () => _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color:
                      active
                          ? Colors.white.withValues(alpha: 0.16)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  labels[index],
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color:
                        active
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.42),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── 工具网格（音质 / 音效 / 倍速 / 音量 / 定时 / 信息） ──
  //
  // 原来这六颗是**一行横向滚动**的胶囊：屏幕放得下 4 颗，剩下两颗在屏幕外面，
  // 用户不往左滑根本不知道「定时」和「信息」存在。而且一排胶囊的观感很像调试
  // 面板，压住整页的视觉重心。
  //
  // 改成 3×2 的等宽网格：六颗一次全露出来，每颗都带图标，扫一眼就知道点哪儿；
  // 网格贴满宽度、行高 38，比原来那行只高 50pt，不会跟唱片抢地方。
  Widget _buildToolGrid(
    Song? song,
    Color primaryColor,
    SettingsState settings,
    SettingsStateNotifier settingsNotifier,
    PlayerController controller,
    String actualQuality,
    bool isPreview,
  ) {
    final quality = settings.playbackQuality;
    final volume = settings.volume;
    final eqPreset = settings.eqPreset;
    final speed = settings.playbackSpeed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _ToolTile(
                  icon: Icons.high_quality_rounded,
                  label: _actualBadge(actualQuality, isPreview),
                  // 只有真拿到档位信息才点亮：拿不到时显示「音质」却仍然高亮，
                  // 会让人以为已经选了什么特殊档位。
                  active: actualQuality.isNotEmpty,
                  activeColor:
                      isPreview ? const Color(0xFFFFC857) : primaryColor,
                  onTap:
                      () => showQualityPicker(
                        context,
                        current: quality,
                        controller: controller,
                        settingsNotifier: settingsNotifier,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ToolTile(
                  icon: Icons.equalizer_rounded,
                  // 之前直接把 eqPreset 的原始 id（pop/rock/vocal）当标签，
                  // 一换音效格子里就蹦出个英文单词。用预设的中文名。
                  label:
                      eqPreset == 'flat'
                          ? '音效'
                          : (EqService.findById(eqPreset)?.label ?? '音效'),
                  active: eqPreset != 'flat',
                  activeColor: primaryColor,
                  onTap:
                      () => showEqPicker(
                        context,
                        currentPreset: eqPreset,
                        settingsNotifier: settingsNotifier,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ToolTile(
                  icon: Icons.speed_rounded,
                  label: speed == 1.0 ? '倍速' : '${speed}x',
                  active: speed != 1.0,
                  activeColor: primaryColor,
                  onTap:
                      () => showSpeedPicker(
                        context,
                        currentSpeed: speed,
                        controller: controller,
                        settingsNotifier: settingsNotifier,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ToolTile(
                  icon:
                      volume <= 0
                          ? Icons.volume_off_rounded
                          : volume < 0.5
                          ? Icons.volume_down_rounded
                          : Icons.volume_up_rounded,
                  // 满音量时写「音量」，调过之后直接显示百分比——
                  // 满音量写 100 是个没人会去解读的数字。
                  label: volume >= 0.995 ? '音量' : '${(volume * 100).round()}%',
                  active: volume < 0.995,
                  activeColor: primaryColor,
                  onTap:
                      () => showVolumeSheet(
                        context,
                        settings: settings,
                        settingsNotifier: settingsNotifier,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _SleepTimerTile(primaryColor: primaryColor)),
              const SizedBox(width: 8),
              Expanded(
                child: _ToolTile(
                  icon: Icons.info_outline_rounded,
                  label: '信息',
                  active: false,
                  activeColor: primaryColor,
                  onTap: () => showSongInfo(context, song),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 进度条 ──────────────────────────────────────────
  Widget _buildProgressBar(
    Duration position,
    Duration duration,
    PlayerController controller,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
              thumbColor: Colors.white,
              overlayColor: Colors.white.withValues(alpha: 0.2),
            ),
            child: Slider(
              value:
                  _isDragging
                      ? _dragValue
                      : (duration.inMilliseconds > 0
                          ? (position.inMilliseconds / duration.inMilliseconds)
                              .clamp(0.0, 1.0)
                          : 0.0),
              onChangeStart: (v) {
                setState(() {
                  _isDragging = true;
                  _dragValue = v;
                });
              },
              onChanged:
                  duration.inMilliseconds > 0
                      ? (v) {
                        setState(() => _dragValue = v);
                      }
                      : null,
              onChangeEnd:
                  duration.inMilliseconds > 0
                      ? (v) {
                        controller.seekTo(
                          Duration(
                            milliseconds: (v * duration.inMilliseconds).round(),
                          ),
                        );
                        setState(() => _isDragging = false);
                      }
                      : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  // 拖动时左端跟着拇指走：原来一直显示播放进度，
                  // 手指拖到哪儿、要跳到哪一秒完全看不出来。
                  _formatDuration(
                    _isDragging && duration.inMilliseconds > 0
                        ? Duration(
                          milliseconds:
                              (_dragValue * duration.inMilliseconds).round(),
                        )
                        : position,
                  ),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
                Text(
                  _formatDuration(duration),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 主控制栏（5 按钮） ─────────────────────────────
  Widget _buildMainControls({
    required bool isPlaying,
    required PlayerController controller,
    required QueueState queueState,
    required QueueStateNotifier queueNotifier,
    required PlayMode playMode,
    required SettingsState settings,
    required Color primaryColor,
    required Color bgColorDark,
    required BuildContext context,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 播放模式
          IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                _playModeIcon(playMode),
                key: ValueKey(playMode),
                color:
                    playMode != PlayMode.list
                        ? primaryColor
                        : Colors.white.withValues(alpha: 0.7),
                size: 22,
              ),
            ),
            onPressed: () => queueNotifier.cyclePlayMode(),
          ),
          // 上一曲
          IconButton(
            icon: Icon(
              Icons.skip_previous,
              color: Colors.white.withValues(alpha: 0.9),
            ),
            iconSize: 36,
            onPressed:
                queueState.songs.isEmpty
                    ? null
                    : () {
                      HapticFeedback.selectionClick();
                      controller.skipPrevious(
                        queue: queueState.songs,
                        currentIndex: queueState.currentIndex,
                        playMode: playMode,
                        quality: settings.playbackQuality,
                      );
                    },
          ),
          // 播放/暂停
          Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 4,
            shadowColor: primaryColor.withValues(alpha: 0.4),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                HapticFeedback.mediumImpact();
                controller.toggle();
              },
              child: SizedBox(
                width: 64,
                height: 64,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    key: ValueKey(isPlaying),
                    color: bgColorDark,
                    size: 36,
                  ),
                ),
              ),
            ),
          ),
          // 下一曲
          IconButton(
            icon: Icon(
              Icons.skip_next,
              color: Colors.white.withValues(alpha: 0.9),
            ),
            iconSize: 36,
            onPressed:
                queueState.songs.isEmpty
                    ? null
                    : () {
                      HapticFeedback.selectionClick();
                      controller.skipNext(
                        queue: queueState.songs,
                        currentIndex: queueState.currentIndex,
                        playMode: playMode,
                        quality: settings.playbackQuality,
                      );
                    },
          ),
          // 队列
          IconButton(
            icon: Icon(
              Icons.queue_music,
              color: Colors.white.withValues(alpha: 0.7),
              size: 22,
            ),
            onPressed: () => showQueueSheet(context),
          ),
        ],
      ),
    );
  }

  /// 没有封面时的占位：品牌图形，而不是一块主色 + 音符。
  ///
  /// 用 SizedBox.expand 让它在 ClipOval 里铺满唱片圆盘——图片本身带渐变，
  /// 铺满后和唱片边缘对齐，看不出是「占位」。
  Widget _defaultCover() {
    return const SizedBox.expand(child: BrandPlaceholder(fit: BoxFit.cover));
  }

  IconData _playModeIcon(PlayMode mode) {
    switch (mode) {
      case PlayMode.list:
        return Icons.repeat;
      case PlayMode.single:
        return Icons.repeat_one;
      case PlayMode.random:
        return Icons.shuffle;
    }
  }
}

// ── 工具格（播放页底部 3×2 网格里的一个） ──────────────
//
// 等宽铺开而不是按内容自适应：六颗格子宽度一致，两行排下来像一块面板，
// 而不是「三颗碰巧撞在一起」。图标在上、字在下，中文短标签不会被挤成两行。
class _ToolTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback? onTap;

  const _ToolTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tint = active ? activeColor : Colors.white.withValues(alpha: 0.78);
    return Material(
      color:
          active
              ? activeColor.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  active
                      ? activeColor.withValues(alpha: 0.45)
                      : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: tint),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tint,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 睡眠定时格 ──────────────────────────────────────
class _SleepTimerTile extends ConsumerWidget {
  final Color primaryColor;
  const _SleepTimerTile({required this.primaryColor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timerState = ref.watch(sleepTimerProvider);
    final timerNotifier = ref.read(sleepTimerProvider.notifier);
    final player = ref.read(playerControllerProvider.notifier);

    // Wire up the onExpired callback — fade out then pause
    timerNotifier.onExpired = () => player.fadeOutAndPause();

    final remaining = timerState.remaining;
    final label =
        timerState.active && remaining != null
            ? (remaining.inMinutes > 0
                ? '${remaining.inMinutes}分'
                : '${remaining.inSeconds}秒')
            : '定时';

    return _ToolTile(
      icon: Icons.bedtime_outlined,
      label: label,
      active: timerState.active,
      activeColor: primaryColor,
      onTap: () => showSleepTimerSheet(context, timerState, timerNotifier),
    );
  }
}
