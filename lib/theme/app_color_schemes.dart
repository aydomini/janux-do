import 'package:flutter/material.dart';

class AppColorSchemePair {
  const AppColorSchemePair({required this.light, required this.dark});

  final ColorScheme light;
  final ColorScheme dark;
}

class AppColorSchemes {
  const AppColorSchemes._();

  static const gruvboxLightMedium = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF076678),
    onPrimary: Color(0xFFFBF1C7),
    primaryContainer: Color(0xFFEBDDB2),
    onPrimaryContainer: Color(0xFF3C3836),
    secondary: Color(0xFF458588),
    onSecondary: Color(0xFFFBF1C7),
    secondaryContainer: Color(0xFFD5C4A1),
    onSecondaryContainer: Color(0xFF3C3836),
    tertiary: Color(0xFFB57614),
    onTertiary: Color(0xFFFBF1C7),
    tertiaryContainer: Color(0xFFEBDDB2),
    onTertiaryContainer: Color(0xFF3C3836),
    error: Color(0xFF9D0006),
    onError: Color(0xFFFBF1C7),
    errorContainer: Color(0xFFCC241D),
    onErrorContainer: Color(0xFFFBF1C7),
    surface: Color(0xFFFBF1C7),
    onSurface: Color(0xFF3C3836),
    surfaceDim: Color(0xFFEBDDB2),
    surfaceBright: Color(0xFFFBF1C7),
    surfaceContainerLowest: Color(0xFFFBF1C7),
    surfaceContainerLow: Color(0xFFF2E5BC),
    surfaceContainer: Color(0xFFF2E5BC),
    surfaceContainerHigh: Color(0xFFEBDDB2),
    surfaceContainerHighest: Color(0xFFEBDDB2),
    onSurfaceVariant: Color(0xFF504945),
    outline: Color(0xFF7C6F64),
    outlineVariant: Color(0xFFEBDDB2),
    shadow: Color(0xFF3C3836),
    scrim: Color(0xFF3C3836),
    inverseSurface: Color(0xFF3C3836),
    onInverseSurface: Color(0xFFFBF1C7),
    inversePrimary: Color(0xFF83A598),
    surfaceTint: Color(0xFF076678),
  );

  static const templeDark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFE4F222),
    onPrimary: Color(0xFF02120C),
    primaryContainer: Color(0xFF4F5E13),
    onPrimaryContainer: Color(0xFFE4F222),
    secondary: Color(0xFF859419),
    onSecondary: Color(0xFF02120C),
    secondaryContainer: Color(0xFF1D2D0F),
    onSecondaryContainer: Color(0xFFC7E6DA),
    tertiary: Color(0xFF788617),
    onTertiary: Color(0xFF02120C),
    tertiaryContainer: Color(0xFF394D46),
    onTertiaryContainer: Color(0xFFC7E6DA),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF02120C),
    onSurface: Color(0xFFC7E6DA),
    surfaceDim: Color(0xFF02120C),
    surfaceBright: Color(0xFF1D2D0F),
    surfaceContainerLowest: Color(0xFF02120C),
    surfaceContainerLow: Color(0xFF0B1A10),
    surfaceContainer: Color(0xFF1D2D0F),
    surfaceContainerHigh: Color(0xFF263616),
    surfaceContainerHighest: Color(0xFF394D46),
    onSurfaceVariant: Color(0xFFC7E6DA),
    outline: Color(0xFF394D46),
    outlineVariant: Color(0xFF4F5E13),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFC7E6DA),
    onInverseSurface: Color(0xFF02120C),
    inversePrimary: Color(0xFF4F5E13),
    surfaceTint: Color(0xFFE4F222),
  );

  static AppColorSchemePair resolve({
    required bool useDynamicColor,
    required Color seedColor,
    required DynamicSchemeVariant schemeVariant,
    ColorScheme? lightDynamic,
    ColorScheme? darkDynamic,
  }) {
    if (useDynamicColor && lightDynamic != null && darkDynamic != null) {
      return AppColorSchemePair(
        light: ColorScheme.fromSeed(
          seedColor: lightDynamic.primary,
          brightness: Brightness.light,
          dynamicSchemeVariant: schemeVariant,
        ),
        dark: ColorScheme.fromSeed(
          seedColor: darkDynamic.primary,
          brightness: Brightness.dark,
          dynamicSchemeVariant: schemeVariant,
        ),
      );
    }

    return const AppColorSchemePair(
      light: gruvboxLightMedium,
      dark: templeDark,
    );
  }
}
