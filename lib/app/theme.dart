import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// NetSeye's palette: dark glass. Surfaces are white at low opacity over a
/// deep, softly lit backdrop, edges are bright hairlines, and one system
/// blue is the only "action" colour.
abstract final class Palette {
  static const ink = Color(0xFF07080C); // deepest background
  static const coal = Color(0x14FFFFFF); // glass panels, cards
  static const slate = Color(0x1FFFFFFF); // raised controls, inputs
  static const line = Color(0x2BFFFFFF); // glass edges, hairlines
  static const bone = Color(0xFFF5F5F7); // primary text
  static const ash = Color(0xFFA1A1A6); // secondary text
  static const dusk = Color(0xFF6E6E73); // tertiary text, disabled
  static const accent = Color(0xFF0A84FF); // the one action colour
  static const onAccent = Color(0xFFFFFFFF); // text / icons on accent
  static const ember = Color(0xFFFF453A); // alerts, offline
  static const moss = Color(0xFF30D158); // healthy, online
}

/// Motion tokens. Everything eases out of the way; nothing bounces.
abstract final class Motion {
  static const quick = Duration(milliseconds: 160);
  static const base = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 480);
  static const ease = Cubic(0.2, 0.0, 0.0, 1.0); // calm deceleration
  static const glide = Cubic(0.32, 0.72, 0.0, 1.0); // for big surfaces
}

/// Inter throughout (the closest open font to Apple's San Francisco), with
/// its display optical size for big titles; Plex Mono only for addresses.
abstract final class Typo {
  static TextStyle _sans(
    double size,
    double weight, {
    Color color = Palette.bone,
    double height = 1.35,
    double tracking = 0,
  }) => TextStyle(
    fontFamily: 'Inter',
    fontSize: size,
    height: height,
    letterSpacing: tracking,
    color: color,
    fontVariations: [FontVariation('wght', weight), FontVariation('opsz', size.clamp(14, 32).toDouble())],
  );

  /// Big titles: camera names, screen titles, the clock. Tight and bold,
  /// the way large titles look on Apple devices.
  static TextStyle display(double size, {Color color = Palette.bone, bool italic = false}) => TextStyle(
    fontFamily: 'Inter',
    fontSize: size,
    height: 1.05,
    letterSpacing: -0.022 * size,
    color: color,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    fontVariations: [FontVariation('wght', italic ? 480 : 680), const FontVariation('opsz', 32)],
  );

  static final body = _sans(15, 400);
  static final bodyStrong = _sans(15, 560);
  static final small = _sans(13, 430, color: Palette.ash);
  static final button = _sans(14, 590, tracking: -0.1);

  /// Small uppercase labels: room, status.
  static TextStyle label({Color color = Palette.ash, double size = 11}) => TextStyle(
    fontFamily: 'Inter',
    fontSize: size,
    letterSpacing: 0.6,
    height: 1.2,
    color: color,
    fontVariations: const [FontVariation('wght', 600), FontVariation('opsz', 14)],
  );

  /// Addresses and stream links.
  static TextStyle mono({Color color = Palette.ash, double size = 13}) =>
      TextStyle(fontFamily: 'PlexMono', fontSize: size, color: color, height: 1.3);
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    surface: Palette.ink,
    onSurface: Palette.bone,
    primary: Palette.accent,
    onPrimary: Palette.onAccent,
    secondary: Palette.ash,
    error: Palette.ember,
    outline: Palette.line,
  );
  OutlineInputBorder edge(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: c, width: w),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // Pages are see-through: the lit backdrop (see [Backdrop]) shows behind
    // every screen, which is what makes the glass read as glass.
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Palette.ink,
    fontFamily: 'Inter',
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
      },
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: Palette.accent,
      selectionColor: Palette.accent.withValues(alpha: 0.35),
      selectionHandleColor: Palette.accent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.coal,
      labelStyle: Typo.small,
      floatingLabelStyle: Typo.label(color: Palette.accent),
      hintStyle: Typo.small.copyWith(color: Palette.dusk),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: edge(Palette.line),
      enabledBorder: edge(Palette.line),
      focusedBorder: edge(Palette.accent, 1.2),
      errorBorder: edge(Palette.ember.withValues(alpha: 0.7)),
      focusedErrorBorder: edge(Palette.ember, 1.2),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Palette.moss : Palette.slate,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Color(0xFF1C1C1E)),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Palette.bone,
      contentTextStyle: Typo.bodyStrong.copyWith(color: Palette.ink),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

const systemChrome = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  systemNavigationBarColor: Palette.ink,
  systemNavigationBarIconBrightness: Brightness.light,
);
