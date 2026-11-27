import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../domain/state/settings_state.dart';
import '../../presentation/debug/debug_console.dart';
import '../../domain/state/queue_state.dart';
import '../../services/player_controller.dart';
import '../player/player_bar.dart';
import '../search/search_panel.dart';
import '../discover/discover_screen.dart';
import '../my/my_screen.dart';
import '../settings/settings_screen.dart';
import '../now_playing/open_now_playing.dart';
import '../widgets/solara_ui.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      const SearchPanel(),
      const DiscoverScreen(),
      const MyScreen(),
      const SettingsScreen(),
    ];
  }

  @override
  void reassemble() {
    super.reassemble();
    ref.read(playerControllerProvider.notifier).pause();
  }

  static const _tabs = [
    _TabItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: '首页',
    ),
    _TabItem(
      icon: Icons.explore_outlined,
      activeIcon: Icons.explore_rounded,
      label: '发现',
    ),
    _TabItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: '我的',
    ),
    _TabItem(
      icon: Icons.tune_rounded,
      activeIcon: Icons.tune_rounded,
      label: '设置',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsStateProvider);
    final debugMode = settings.debugMode;

    final isMac = Platform.isMacOS;

    if (isMac) {
      return _MacLayout(
        currentIndex: _currentIndex,
        tabs: _tabs,
        pages: _pages,
        debugMode: debugMode,
        onTap: (i) => setState(() => _currentIndex = i),
      );
    }

    // 布局：内容 → 播放条 → 悬浮导航胶囊。
    // 播放条不做「浮在内容之上」的绝对定位，否则各页可滚动内容会被它遮住一条，
    // 需要每页手动补底部内边距，改漏一处就是一屏内容被压掉。
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: IndexedStack(index: _currentIndex, children: _pages)),
          if (debugMode) const DebugConsole(),
          const PlayerBar(),
        ],
      ),
      bottomNavigationBar: _FloatingNavBar(
        currentIndex: _currentIndex,
        tabs: _tabs,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

// ── macOS 侧边栏布局 ────────────────────────────────────────────────────────

class _MacLayout extends ConsumerWidget {
  final int currentIndex;
  final List<_TabItem> tabs;
  final List<Widget> pages;
  final bool debugMode;
  final ValueChanged<int> onTap;

  const _MacLayout({
    required this.currentIndex,
    required this.tabs,
    required this.pages,
    required this.debugMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Row(
        children: [
          _MacSidebar(
            currentIndex: currentIndex,
            tabs: tabs,
            isDark: isDark,
            colorScheme: colorScheme,
            onTap: onTap,
          ),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: IndexedStack(index: currentIndex, children: pages),
                    ),
                  ),
                ),
                if (debugMode) const DebugConsole(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MacSidebar extends ConsumerWidget {
  final int currentIndex;
  final List<_TabItem> tabs;
  final bool isDark;
  final ColorScheme colorScheme;
  final ValueChanged<int> onTap;

  const _MacSidebar({
    required this.currentIndex,
    required this.tabs,
    required this.isDark,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 216,
      decoration: BoxDecoration(
        color:
            isDark ? SolaraColors.darkSurfaceLow : SolaraColors.lightSurfaceLow,
        border: Border(
          right: BorderSide(
            color:
                isDark
                    ? SolaraColors.darkOutlineVariant
                    : SolaraColors.lightOutlineVariant,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: SolaraColors.sunset),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Solara',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          ...List.generate(tabs.length, (i) {
            final tab = tabs[i];
            final selected = i == currentIndex;
            return _SidebarItem(
              icon: selected ? tab.activeIcon : tab.icon,
              label: tab.label,
              selected: selected,
              colorScheme: colorScheme,
              onTap: () => onTap(i),
            );
          }),
          const Spacer(),
          const _SidebarPlayer(),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color:
            selected
                ? colorScheme.primary.withValues(alpha: 0.14)
                : Colors.transparent,
        borderRadius: SolaraRadius.tileRadius,
        child: InkWell(
          borderRadius: SolaraRadius.tileRadius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 19,
                  color:
                      selected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 11),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color:
                        selected ? colorScheme.primary : colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarPlayer extends ConsumerWidget {
  const _SidebarPlayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final settings = ref.watch(settingsStateProvider);
    final queueState = ref.watch(queueStateProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final position = state.position;
    final duration = state.duration ?? Duration.zero;
    final progress =
        duration.inMilliseconds > 0
            ? (position.inMilliseconds / duration.inMilliseconds).clamp(
              0.0,
              1.0,
            )
            : 0.0;

    return GestureDetector(
      onTap: state.currentSong == null ? null : () => openNowPlaying(context),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
        decoration: BoxDecoration(
          color:
              isDark ? SolaraColors.darkSurfaceHigh : SolaraColors.lightSurface,
          borderRadius: SolaraRadius.cardRadius,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              state.currentSong?.name ?? '未在播放',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (state.currentSong != null)
              Text(
                state.currentSong!.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 2.5,
                backgroundColor: colorScheme.onSurface.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed:
                      queueState.songs.isEmpty
                          ? null
                          : () => controller.skipPrevious(
                            queue: queueState.songs,
                            currentIndex: queueState.currentIndex,
                            playMode: queueState.playMode,
                            quality: settings.playbackQuality,
                          ),
                  icon: const Icon(Icons.skip_previous_rounded),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                Material(
                  color:
                      state.currentSong != null
                          ? colorScheme.primary
                          : colorScheme.onSurface.withValues(alpha: 0.1),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: state.currentSong != null ? controller.toggle : null,
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: Icon(
                        state.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color:
                            state.currentSong != null
                                ? SolaraColors.onAccent(colorScheme.primary)
                                : colorScheme.onSurface.withValues(alpha: 0.3),
                        size: 19,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed:
                      queueState.songs.isEmpty
                          ? null
                          : () => controller.skipNext(
                            queue: queueState.songs,
                            currentIndex: queueState.currentIndex,
                            playMode: queueState.playMode,
                            quality: settings.playbackQuality,
                          ),
                  icon: const Icon(Icons.skip_next_rounded),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── iOS/通用底部导航 ─────────────────────────────────────────────────────────
//
// 悬浮胶囊式：左右留白、圆角、毛玻璃、选中项带一层浅色底。
// 实心通栏导航（Material 默认）在这种图片密集的音乐 App 里显得很「工具感」。
class _FloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final List<_TabItem> tabs;
  final ValueChanged<int> onTap;

  const _FloatingNavBar({
    required this.currentIndex,
    required this.tabs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, (bottomPadding > 0 ? 6 : 12)),
      child: GlassSurface(
        blur: 30,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color:
              isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.black.withValues(alpha: 0.05),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: List.generate(tabs.length, (i) {
              final tab = tabs[i];
              final selected = i == currentIndex;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color:
                          selected
                              ? scheme.primary.withValues(
                                alpha: isDark ? 0.20 : 0.14,
                              )
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          selected ? tab.activeIcon : tab.icon,
                          size: 21,
                          color:
                              selected
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          tab.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color:
                                selected
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _TabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
