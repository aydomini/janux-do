import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/theme/app_color_schemes.dart';

void main() {
  test('默认日间主题使用 Codex Gruvbox Light Medium 色值', () {
    final scheme = AppColorSchemes.gruvboxLightMedium;

    expect(scheme.brightness, Brightness.light);
    expect(scheme.surface.toARGB32(), 0xFFFBF1C7);
    expect(scheme.onSurface.toARGB32(), 0xFF3C3836);
    expect(scheme.surfaceContainer.toARGB32(), 0xFFF2E5BC);
    expect(scheme.surfaceContainerHighest.toARGB32(), 0xFFEBDDB2);
    expect(scheme.primary.toARGB32(), 0xFF076678);
    expect(scheme.secondary.toARGB32(), 0xFF458588);
    expect(scheme.outlineVariant.toARGB32(), 0xFFEBDDB2);
  });

  test('默认夜间主题使用 Codex Temple Dark 色值', () {
    final scheme = AppColorSchemes.templeDark;

    expect(scheme.brightness, Brightness.dark);
    expect(scheme.surface.toARGB32(), 0xFF02120C);
    expect(scheme.onSurface.toARGB32(), 0xFFC7E6DA);
    expect(scheme.surfaceContainer.toARGB32(), 0xFF1D2D0F);
    expect(scheme.primary.toARGB32(), 0xFFE4F222);
    expect(scheme.onPrimary.toARGB32(), 0xFF02120C);
    expect(scheme.outline.toARGB32(), 0xFF394D46);
    expect(scheme.outlineVariant.toARGB32(), 0xFF4F5E13);
  });

  test('未启用动态色时解析为 Codex Gruvbox 和 Temple 默认主题', () {
    final schemes = AppColorSchemes.resolve(
      useDynamicColor: false,
      seedColor: Colors.blue,
      schemeVariant: DynamicSchemeVariant.tonalSpot,
    );

    expect(schemes.light, AppColorSchemes.gruvboxLightMedium);
    expect(schemes.dark, AppColorSchemes.templeDark);
  });

  test('启用动态色且系统色可用时保留动态色优先级', () {
    final dynamicLight = ColorScheme.fromSeed(
      seedColor: Colors.purple,
      brightness: Brightness.light,
    );
    final dynamicDark = ColorScheme.fromSeed(
      seedColor: Colors.green,
      brightness: Brightness.dark,
    );

    final schemes = AppColorSchemes.resolve(
      useDynamicColor: true,
      lightDynamic: dynamicLight,
      darkDynamic: dynamicDark,
      seedColor: Colors.blue,
      schemeVariant: DynamicSchemeVariant.tonalSpot,
    );

    expect(schemes.light.primary, dynamicLight.primary);
    expect(schemes.dark.primary, dynamicDark.primary);
    expect(
      schemes.light.surface,
      isNot(AppColorSchemes.gruvboxLightMedium.surface),
    );
    expect(schemes.dark.surface, isNot(AppColorSchemes.templeDark.surface));
  });
}
