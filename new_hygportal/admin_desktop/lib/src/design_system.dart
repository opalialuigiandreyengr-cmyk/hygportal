part of '../main.dart';

class Kicker extends StatelessWidget {
  const Kicker(this.text, {this.dark = false, super.key});

  final String text;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: HygTypography.kicker.copyWith(
        color: dark ? HygColors.goldStrong : HygColors.gold,
      ),
    );
  }
}

class HygColors {
  static const background = Color(0xFFF8FAFC);
  static const border = Color(0xFFDBE4EF);
  static const gold = Color(0xFFFACC15);
  static const goldStrong = Color(0xFFEAB308);
  static const ink = Color(0xFF071426);
  static const muted = Color(0xFF64748B);
  static const panel = Color(0xFF0F172A);
  static const panelSoft = Color(0xFF111827);
}

class HygTypography {
  static const bodyFontFamily = 'Inter';
  static const headingFontFamily = 'Poppins';
  static const fontFamily = bodyFontFamily;
  static const fontFallbacks = ['Segoe UI', 'Arial'];
  static const headingFallbacks = ['Inter', 'Segoe UI', 'Arial'];

  static const TextStyle display = TextStyle(
    fontFamily: headingFontFamily,
    fontFamilyFallback: headingFallbacks,
    color: Colors.white,
    fontSize: 30,
    height: 1.08,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  static const TextStyle pageTitle = TextStyle(
    fontFamily: headingFontFamily,
    fontFamilyFallback: headingFallbacks,
    color: HygColors.ink,
    fontSize: 21,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  static const TextStyle cardTitle = TextStyle(
    fontFamily: headingFontFamily,
    fontFamilyFallback: headingFallbacks,
    color: Color(0xFF111827),
    fontSize: 30,
    height: 1.05,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  static const TextStyle loginWelcome = TextStyle(
    fontFamily: headingFontFamily,
    fontFamilyFallback: headingFallbacks,
    color: Colors.white,
    fontSize: 30,
    height: 1.08,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );

  static const TextStyle loginTitle = TextStyle(
    fontFamily: headingFontFamily,
    fontFamilyFallback: headingFallbacks,
    color: Color(0xFF111827),
    fontSize: 30,
    height: 1.05,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
  );

  static const TextStyle body = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: fontFallbacks,
    color: HygColors.muted,
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: fontFallbacks,
    color: HygColors.muted,
    fontSize: 15,
    height: 1.45,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  static const TextStyle kicker = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: fontFallbacks,
    color: HygColors.gold,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );

  static const TextStyle fieldLabel = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: fontFallbacks,
    color: Color(0xFF475569),
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  static const TextStyle input = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: fontFallbacks,
    color: Color(0xFF111827),
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  );

  static const TextStyle button = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: fontFallbacks,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  static const TextStyle nav = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: fontFallbacks,
    color: Colors.white,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  );

  static const TextStyle tableHeader = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: fontFallbacks,
    color: Color(0xFF475569),
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );

  static const TextStyle tablePrimary = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: fontFallbacks,
    color: HygColors.ink,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );

  static const TextStyle tableBody = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: fontFallbacks,
    color: HygColors.ink,
    fontSize: 13,
    height: 1.25,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  );

  static const TextStyle tableMuted = TextStyle(
    fontFamily: bodyFontFamily,
    fontFamilyFallback: fontFallbacks,
    color: HygColors.muted,
    fontSize: 11,
    letterSpacing: 0,
  );

  static TextTheme get textTheme => const TextTheme(
    displayLarge: display,
    headlineLarge: cardTitle,
    titleLarge: pageTitle,
    bodyMedium: body,
    labelMedium: fieldLabel,
  );
}
