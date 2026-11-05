import 'package:flutter/material.dart';

import 'motion.dart';

/// Token theo logo Cleanify: xám than (#2A343F), xám xanh nhạt, nhấn lime. Lime nền
/// (#A3D133) cho gradient/huy hiệu, lime đậm (#557800) cho chữ và icon trên nền sáng
/// (tương phản >= 4,5). Gradient nhấn chạy từ lime sáng sang lime đậm.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.surfaceAlt,
    required this.line,
    required this.stroke,
    required this.text2,
    required this.text3,
    required this.accent1,
    required this.accent2,
    required this.accentSoft,
    required this.tint1,
    required this.tint2,
  });

  final Color surfaceAlt; // --sb
  final Color line; // --hr
  final Color stroke; // --st
  final Color text2;
  final Color text3;
  final Color accent1;
  final Color accent2;
  final Color accentSoft; // lime sáng, đầu sáng của gradient
  final Color tint1;
  final Color tint2;

  LinearGradient get gradient => LinearGradient(colors: [accentSoft, accent1]);

  static const light = AppColors(
    surfaceAlt: Color(0xFFEBEEF4),
    line: Color(0xFFDFE3EC),
    stroke: Color(0xFFC3C9D6),
    text2: Color(0xFF4A5666),
    text3: Color(0xFF6B7686),
    accent1: Color(0xFF557800),
    accent2: Color(0xFF3E4A5A),
    accentSoft: Color(0xFFA3D133),
    tint1: Color(0x38A3D133),
    tint2: Color(0x1F3E4A5A),
  );

  static const dark = AppColors(
    surfaceAlt: Color(0xFF232A33),
    line: Color(0xFF2E3640),
    stroke: Color(0xFF4A5563),
    text2: Color(0xFFB7C0CC),
    text3: Color(0xFF98A3B1),
    accent1: Color(0xFFB5DC4A),
    accent2: Color(0xFFA4ADBC),
    accentSoft: Color(0xFFD2EC82),
    tint1: Color(0x33B5DC4A),
    tint2: Color(0x2EA4ADBC),
  );

  @override
  AppColors copyWith({
    Color? surfaceAlt,
    Color? line,
    Color? stroke,
    Color? text2,
    Color? text3,
    Color? accent1,
    Color? accent2,
    Color? accentSoft,
    Color? tint1,
    Color? tint2,
  }) =>
      AppColors(
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        line: line ?? this.line,
        stroke: stroke ?? this.stroke,
        text2: text2 ?? this.text2,
        text3: text3 ?? this.text3,
        accent1: accent1 ?? this.accent1,
        accent2: accent2 ?? this.accent2,
        accentSoft: accentSoft ?? this.accentSoft,
        tint1: tint1 ?? this.tint1,
        tint2: tint2 ?? this.tint2,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      line: Color.lerp(line, other.line, t)!,
      stroke: Color.lerp(stroke, other.stroke, t)!,
      text2: Color.lerp(text2, other.text2, t)!,
      text3: Color.lerp(text3, other.text3, t)!,
      accent1: Color.lerp(accent1, other.accent1, t)!,
      accent2: Color.lerp(accent2, other.accent2, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      tint1: Color.lerp(tint1, other.tint1, t)!,
      tint2: Color.lerp(tint2, other.tint2, t)!,
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get appColors =>
      Theme.of(this).extension<AppColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? AppColors.dark
          : AppColors.light);
}

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final x = dark ? AppColors.dark : AppColors.light;
  final bg = dark ? const Color(0xFF12161B) : const Color(0xFFF2F4FA);
  final surface = dark ? const Color(0xFF1A2027) : Colors.white;
  final ink = dark ? const Color(0xFFF2F4F8) : const Color(0xFF2A343F);
  final inkOn = dark ? const Color(0xFF14181D) : Colors.white;
  final danger = dark ? const Color(0xFFF2686C) : const Color(0xFFD13438);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: ink,
    onPrimary: inkOn,
    secondary: x.accent1,
    onSecondary: dark ? const Color(0xFF14181D) : Colors.white,
    error: danger,
    onError: dark ? const Color(0xFF1A0A07) : Colors.white,
    surface: surface,
    onSurface: ink,
    outline: x.line,
    surfaceTint: Colors.transparent,
  );

  final shape16 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    extensions: [x],
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // Không ép full-width: nút trong dialog/Row sẽ giãn vô hạn. Trang nào cần
        // nút rộng thì tự bọc SizedBox(width: double.infinity).
        minimumSize: const Size(64, 48),
        shape: shape16,
        backgroundColor: const Color(0xFFE8ECF3),
        foregroundColor: const Color(0xFF2A343F),
        disabledBackgroundColor: const Color(0xFFF0F2F6),
        disabledForegroundColor: const Color(0xFF8A94A3),
        side: const BorderSide(color: Color(0xFFD3D9E4)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: shape16,
        side: BorderSide(color: x.line),
        foregroundColor: ink,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: x.text2),
    ),
    dividerColor: x.line,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeSlidePageTransitionsBuilder(),
    }),
  );
}
