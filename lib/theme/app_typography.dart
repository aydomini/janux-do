import 'package:flutter/material.dart';

class AppTypography {
  const AppTypography._();

  static const double readingBodyFontSize = 18;
  static const double readingBodyHeight = 1.72;

  static TextTheme buildTextTheme({String? fontFamily}) {
    TextStyle style({
      required double size,
      required double height,
      FontWeight weight = FontWeight.w400,
    }) {
      return TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        height: height,
        fontWeight: weight,
        letterSpacing: 0,
      );
    }

    return TextTheme(
      displayLarge: style(size: 48, height: 1.12, weight: FontWeight.w700),
      displayMedium: style(size: 40, height: 1.16, weight: FontWeight.w700),
      displaySmall: style(size: 32, height: 1.2, weight: FontWeight.w700),
      headlineLarge: style(size: 30, height: 1.2, weight: FontWeight.w700),
      headlineMedium: style(size: 26, height: 1.23, weight: FontWeight.w700),
      headlineSmall: style(size: 22, height: 1.27, weight: FontWeight.w700),
      titleLarge: style(size: 20, height: 1.3, weight: FontWeight.w700),
      titleMedium: style(size: 17, height: 1.41, weight: FontWeight.w600),
      titleSmall: style(size: 15, height: 1.47, weight: FontWeight.w600),
      bodyLarge: style(size: 16, height: 1.625),
      bodyMedium: style(size: 14, height: 1.57),
      bodySmall: style(size: 12, height: 1.5),
      labelLarge: style(size: 14, height: 1.43, weight: FontWeight.w600),
      labelMedium: style(size: 12, height: 1.33, weight: FontWeight.w600),
      labelSmall: style(size: 11, height: 1.27, weight: FontWeight.w600),
    );
  }
}
