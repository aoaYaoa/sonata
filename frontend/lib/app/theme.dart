import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Solara 的视觉语言：落日暖色 + 深空底色 + 大圆角。
///
/// 参考 Spotify / 网易云 / QQ 音乐的共同点：
///  - 播放场景整体压暗，封面是绝对主角，颜色只做强调；
///  - 卡片圆角偏大（16~20），图片铺满、文字压在图上或用一行小字托底；
///  - 分隔靠留白和 1px 细线，不靠投影堆叠。
class SolaraColors {
  SolaraColors._();

  /// 主色：落日橙。
  static const brand = Color(0xFFFF7A45);

  /// 次色：霓虹粉，配合主色做渐变。
  static const brandAlt = Color(0xFFFF4D8D);
  static const violet = Color(0xFF7C6BFF);
  static const mint = Color(0xFF35D6A4);
  static const amber = Color(0xFFFFC24B);

  /// 首页「问候语」与各处的强调渐变。
  static const sunset = [Color(0xFFFF9A5C), Color(0xFFFF4D8D)];
  static const dusk = [Color(0xFF7C6BFF), Color(0xFF35D6A4)];

  // ── 暗色基底（比纯黑略暖，长时间看不刺眼）──
  static const darkBg = Color(0xFF0A0A0D);
  static const darkSurfaceLow = Color(0xFF131318);
  static const darkSurface = Color(0xFF191920);
  static const darkSurfaceHigh = Color(0xFF22222B);
  static const darkSurfaceHighest = Color(0xFF2C2C37);
  static const darkOnSurface = Color(0xFFF3F3F7);
  static const darkOnSurfaceVariant = Color(0xFF9E9EAD);
  static const darkOutline = Color(0xFF3A3A46);
  static const darkOutlineVariant = Color(0xFF26262F);

  // ── 亮色基底 ──
  static const lightBg = Color(0xFFF7F7FA);
  static const lightSurfaceLow = Color(0xFFFFFFFF);
  static const lightSurface = Color(0xFFF1F1F5);
  static const lightSurfaceHigh = Color(0xFFE9E9EF);
  static const lightSurfaceHighest = Color(0xFFE0E0E8);
  static const lightOnSurface = Color(0xFF111114);
  static const lightOnSurfaceVariant = Color(0xFF6E6E7A);
  static const lightOutline = Color(0xFFD8D8E0);
  static const lightOutlineVariant = Color(0xFFE7E7EE);

  /// 把任意颜色（通常是专辑封面的主色）拉成「能在深色底上发光」的强调色。
  ///
  /// 封面主色经常是接近黑或灰的色块，直接拿来当强调色会糊成一片，
  /// 所以亮度、饱和度都有下限，过暗过灰时回退到品牌色。
  static Color vivid(Color c, {Color fallback = brand}) {
    final hsl = HSLColor.fromColor(c);
    if (hsl.saturation < 0.22) return fallback;
    return hsl
        .withSaturation(hsl.saturation.clamp(0.45, 0.95))
        .withLightness(hsl.lightness.clamp(0.52, 0.72))
        .toColor();
  }

  /// 强调色上的文字/图标颜色。
  static Color onAccent(Color accent) =>
      ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
          ? Colors.white
          : const Color(0xFF1A1005);
}

/// 圆角与间距的统一取值，避免各页面各写一套魔数。
class SolaraRadius {
  SolaraRadius._();

  static const double card = 18;
  static const double tile = 14;
  static const double thumb = 10;
  static const double sheet = 26;

  static BorderRadius get cardRadius => BorderRadius.circular(card);
  static BorderRadius get tileRadius => BorderRadius.circular(tile);
  static BorderRadius get thumbRadius => BorderRadius.circular(thumb);
  static BorderRadius get sheetRadius =>
      const BorderRadius.vertical(top: Radius.circular(sheet));
}

ThemeData solaraTheme({required Brightness brightness, Color? accent}) {
  final isDark = brightness == Brightness.dark;
  final primary = accent ?? SolaraColors.brand;

  final scheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: brightness,
  ).copyWith(
    primary: primary,
    onPrimary: SolaraColors.onAccent(primary),
    primaryContainer: primary.withValues(alpha: isDark ? 0.22 : 0.14),
    onPrimaryContainer: isDark ? primary : const Color(0xFF5A2600),
    secondary: SolaraColors.brandAlt,
    onSecondary: SolaraColors.onAccent(SolaraColors.brandAlt),
    tertiary: SolaraColors.violet,
    surface: isDark ? SolaraColors.darkBg : SolaraColors.lightBg,
    onSurface:
        isDark ? SolaraColors.darkOnSurface : SolaraColors.lightOnSurface,
    onSurfaceVariant:
        isDark
            ? SolaraColors.darkOnSurfaceVariant
            : SolaraColors.lightOnSurfaceVariant,
    surfaceContainerLowest: isDark ? const Color(0xFF07070A) : Colors.white,
    surfaceContainerLow:
        isDark ? SolaraColors.darkSurfaceLow : SolaraColors.lightSurfaceLow,
    surfaceContainer:
        isDark ? SolaraColors.darkSurface : SolaraColors.lightSurface,
    surfaceContainerHigh:
        isDark ? SolaraColors.darkSurfaceHigh : SolaraColors.lightSurfaceHigh,
    surfaceContainerHighest:
        isDark
            ? SolaraColors.darkSurfaceHighest
            : SolaraColors.lightSurfaceHighest,
    outline: isDark ? SolaraColors.darkOutline : SolaraColors.lightOutline,
    outlineVariant:
        isDark
            ? SolaraColors.darkOutlineVariant
            : SolaraColors.lightOutlineVariant,
    error: const Color(0xFFFF5F6D),
    surfaceTint: primary,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
  );

  // 状态栏文字颜色必须跟随主题：浅色主题下不设的话，
  // iOS 会沿用上一屏（播放页）的白色状态栏文字，压在浅色背景上直接看不见。
  final overlayStyle = (isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark)
      .copyWith(statusBarColor: Colors.transparent);

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    splashFactory: InkSparkle.splashFactory,
    textTheme: _textTheme(scheme),
    primaryTextTheme: _textTheme(scheme),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 16,
      systemOverlayStyle: overlayStyle,
      titleTextStyle: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: scheme.onSurface,
      ),
      iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: SolaraRadius.cardRadius),
      clipBehavior: Clip.antiAlias,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      titleTextStyle: TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      subtitleTextStyle: TextStyle(
        fontSize: 12,
        color: scheme.onSurfaceVariant,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(scheme.onSurfaceVariant),
        visualDensity: VisualDensity.compact,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: SolaraColors.onAccent(primary),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: SolaraRadius.tileRadius),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      selectedColor: primary.withValues(alpha: isDark ? 0.26 : 0.16),
      side: BorderSide.none,
      labelStyle: TextStyle(fontSize: 12.5, color: scheme.onSurface),
      secondaryLabelStyle: TextStyle(fontSize: 12.5, color: primary),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: const StadiumBorder(),
      showCheckmark: false,
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 3,
      activeTrackColor: primary,
      inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.14),
      thumbColor: primary,
      overlayColor: primary.withValues(alpha: 0.16),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      trackShape: const RoundedRectSliderTrackShape(),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected)
                ? SolaraColors.onAccent(primary)
                : scheme.onSurfaceVariant,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected)
                ? primary
                : scheme.surfaceContainerHighest,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isDark ? SolaraColors.darkSurface : Colors.white,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: isDark ? SolaraColors.darkSurface : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: SolaraRadius.sheetRadius),
      showDragHandle: false,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: isDark ? SolaraColors.darkSurface : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: SolaraRadius.cardRadius),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor:
          isDark ? SolaraColors.darkSurfaceHighest : const Color(0xFF23232B),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: SolaraRadius.tileRadius),
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: SolaraRadius.tileRadius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: SolaraRadius.tileRadius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: SolaraRadius.tileRadius,
        borderSide: BorderSide(color: primary.withValues(alpha: 0.6)),
      ),
      hintStyle: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: isDark ? SolaraColors.darkSurfaceHigh : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: SolaraRadius.tileRadius),
      elevation: 8,
      textStyle: TextStyle(fontSize: 14, color: scheme.onSurface),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: primary,
      linearTrackColor: scheme.onSurface.withValues(alpha: 0.12),
      circularTrackColor: Colors.transparent,
    ),
    // iOS/macOS 保持 MaterialPageRoute 的默认 Cupertino 转场；
    // 只给 Android 换成更轻的淡入推进，避免旧版 Zoom 动画的塑料感。
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
    ),
  );
}

TextTheme _textTheme(ColorScheme s) {
  return TextTheme(
    displaySmall: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
      color: s.onSurface,
    ),
    headlineSmall: TextStyle(
      fontSize: 21,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      color: s.onSurface,
    ),
    titleLarge: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      color: s.onSurface,
    ),
    titleMedium: TextStyle(
      fontSize: 15.5,
      fontWeight: FontWeight.w600,
      color: s.onSurface,
    ),
    titleSmall: TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      color: s.onSurface,
    ),
    bodyLarge: TextStyle(fontSize: 15, height: 1.4, color: s.onSurface),
    bodyMedium: TextStyle(fontSize: 13.5, height: 1.35, color: s.onSurface),
    bodySmall: TextStyle(fontSize: 12, height: 1.3, color: s.onSurfaceVariant),
    labelLarge: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: s.onSurface,
    ),
    labelMedium: TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      color: s.onSurfaceVariant,
    ),
    labelSmall: TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w500,
      color: s.onSurfaceVariant,
    ),
  );
}
