import 'package:flutter/material.dart';

class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.warning,
    required this.danger,
    required this.success,
    required this.imagePreviewScrim,
    required this.imagePreviewBackground,
    required this.imagePreviewForeground,
    required this.heatHigh,
    required this.heatMedium,
    required this.heatLow,
    required this.badgeGold,
    required this.badgeSilver,
    required this.badgeBronze,
    required this.shareText,
    required this.shareSecondaryText,
    required this.shareBorder,
    required this.avatarFallback,
  });

  factory AppSemanticColors.fromColorScheme(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    return AppSemanticColors(
      warning: isDark ? scheme.primary : scheme.tertiary,
      danger: scheme.error,
      success: isDark ? scheme.secondary : const Color(0xFF79740E),
      imagePreviewScrim: scheme.scrim,
      imagePreviewBackground: isDark ? scheme.surface : scheme.inverseSurface,
      imagePreviewForeground: isDark
          ? scheme.onSurface
          : scheme.onInverseSurface,
      heatHigh: isDark ? scheme.primary : const Color(0xFFAF3A03),
      heatMedium: isDark ? scheme.secondary : scheme.tertiary,
      heatLow: isDark ? scheme.tertiary : scheme.outline,
      badgeGold: isDark ? scheme.primary : scheme.tertiary,
      badgeSilver: isDark ? scheme.onSurface : scheme.secondary,
      badgeBronze: isDark ? scheme.tertiary : scheme.outline,
      shareText: scheme.onSurface,
      shareSecondaryText: scheme.onSurface.withValues(alpha: 0.62),
      shareBorder: scheme.onSurface.withValues(alpha: 0.12),
      avatarFallback: scheme.surfaceContainerHighest,
    );
  }

  final Color warning;
  final Color danger;
  final Color success;
  final Color imagePreviewScrim;
  final Color imagePreviewBackground;
  final Color imagePreviewForeground;
  final Color heatHigh;
  final Color heatMedium;
  final Color heatLow;
  final Color badgeGold;
  final Color badgeSilver;
  final Color badgeBronze;
  final Color shareText;
  final Color shareSecondaryText;
  final Color shareBorder;
  final Color avatarFallback;

  @override
  AppSemanticColors copyWith({
    Color? warning,
    Color? danger,
    Color? success,
    Color? imagePreviewScrim,
    Color? imagePreviewBackground,
    Color? imagePreviewForeground,
    Color? heatHigh,
    Color? heatMedium,
    Color? heatLow,
    Color? badgeGold,
    Color? badgeSilver,
    Color? badgeBronze,
    Color? shareText,
    Color? shareSecondaryText,
    Color? shareBorder,
    Color? avatarFallback,
  }) {
    return AppSemanticColors(
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      success: success ?? this.success,
      imagePreviewScrim: imagePreviewScrim ?? this.imagePreviewScrim,
      imagePreviewBackground:
          imagePreviewBackground ?? this.imagePreviewBackground,
      imagePreviewForeground:
          imagePreviewForeground ?? this.imagePreviewForeground,
      heatHigh: heatHigh ?? this.heatHigh,
      heatMedium: heatMedium ?? this.heatMedium,
      heatLow: heatLow ?? this.heatLow,
      badgeGold: badgeGold ?? this.badgeGold,
      badgeSilver: badgeSilver ?? this.badgeSilver,
      badgeBronze: badgeBronze ?? this.badgeBronze,
      shareText: shareText ?? this.shareText,
      shareSecondaryText: shareSecondaryText ?? this.shareSecondaryText,
      shareBorder: shareBorder ?? this.shareBorder,
      avatarFallback: avatarFallback ?? this.avatarFallback,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
      imagePreviewScrim: Color.lerp(
        imagePreviewScrim,
        other.imagePreviewScrim,
        t,
      )!,
      imagePreviewBackground: Color.lerp(
        imagePreviewBackground,
        other.imagePreviewBackground,
        t,
      )!,
      imagePreviewForeground: Color.lerp(
        imagePreviewForeground,
        other.imagePreviewForeground,
        t,
      )!,
      heatHigh: Color.lerp(heatHigh, other.heatHigh, t)!,
      heatMedium: Color.lerp(heatMedium, other.heatMedium, t)!,
      heatLow: Color.lerp(heatLow, other.heatLow, t)!,
      badgeGold: Color.lerp(badgeGold, other.badgeGold, t)!,
      badgeSilver: Color.lerp(badgeSilver, other.badgeSilver, t)!,
      badgeBronze: Color.lerp(badgeBronze, other.badgeBronze, t)!,
      shareText: Color.lerp(shareText, other.shareText, t)!,
      shareSecondaryText: Color.lerp(
        shareSecondaryText,
        other.shareSecondaryText,
        t,
      )!,
      shareBorder: Color.lerp(shareBorder, other.shareBorder, t)!,
      avatarFallback: Color.lerp(avatarFallback, other.avatarFallback, t)!,
    );
  }
}

extension AppSemanticColorsTheme on ThemeData {
  AppSemanticColors get appSemanticColors =>
      extension<AppSemanticColors>() ??
      AppSemanticColors.fromColorScheme(colorScheme);
}
