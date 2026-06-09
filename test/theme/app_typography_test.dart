import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/theme/app_typography.dart';

void main() {
  test('AppTypography 构建统一字体等级', () {
    final textTheme = AppTypography.buildTextTheme(fontFamily: 'MiSans');

    expect(textTheme.titleLarge?.fontFamily, 'MiSans');
    expect(textTheme.headlineMedium?.fontSize, 26);
    expect(textTheme.titleLarge?.fontSize, 20);
    expect(textTheme.bodyLarge?.fontSize, 16);
    expect(textTheme.bodyLarge?.height, 1.625);
    expect(textTheme.labelLarge?.fontWeight, FontWeight.w600);
    expect(AppTypography.readingBodyFontSize, 18);
    expect(AppTypography.readingBodyHeight, 1.72);
  });

  test('AppTypography 允许系统字体继承平台默认值', () {
    final textTheme = AppTypography.buildTextTheme();

    expect(textTheme.bodyMedium?.fontFamily, isNull);
    expect(textTheme.bodyMedium?.fontSize, 14);
    expect(textTheme.bodySmall?.height, 1.5);
  });
}
