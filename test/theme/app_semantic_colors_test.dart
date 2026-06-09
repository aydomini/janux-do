import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/theme/app_color_schemes.dart';
import 'package:fluxdo/theme/app_semantic_colors.dart';

void main() {
  test('Codex 默认主题提供统一语义色', () {
    final light = AppSemanticColors.fromColorScheme(
      AppColorSchemes.gruvboxLightMedium,
    );
    final dark = AppSemanticColors.fromColorScheme(AppColorSchemes.templeDark);

    expect(light.warning.toARGB32(), 0xFFB57614);
    expect(light.danger.toARGB32(), 0xFF9D0006);
    expect(light.success.toARGB32(), 0xFF79740E);
    expect(light.imagePreviewBackground.toARGB32(), 0xFF3C3836);
    expect(light.imagePreviewForeground.toARGB32(), 0xFFFBF1C7);
    expect(light.shareText.toARGB32(), 0xFF3C3836);

    expect(dark.warning.toARGB32(), 0xFFE4F222);
    expect(dark.danger.toARGB32(), 0xFFFFB4AB);
    expect(dark.success.toARGB32(), 0xFF859419);
    expect(dark.imagePreviewBackground.toARGB32(), 0xFF02120C);
    expect(dark.imagePreviewForeground.toARGB32(), 0xFFC7E6DA);
    expect(dark.shareText.toARGB32(), 0xFFC7E6DA);
  });

  test('ThemeData 可以读取统一语义色扩展', () {
    final semanticColors = AppSemanticColors.fromColorScheme(
      AppColorSchemes.templeDark,
    );
    final theme = ThemeData(
      colorScheme: AppColorSchemes.templeDark,
      extensions: [semanticColors],
    );

    expect(theme.appSemanticColors, semanticColors);
    expect(theme.appSemanticColors.heatHigh, semanticColors.heatHigh);
  });

  test('JavBus 主页面不保留预览相关硬编码黑白色', () {
    final file = File('lib/pages/javbus/javbus_thread_page.dart');
    final source = file.readAsStringSync();

    expect(source, isNot(contains('Colors.black')));
    expect(source, isNot(contains('Colors.white70')));
  });

  test('主阅读和高频通用组件不保留散落状态色硬编码', () {
    const paths = [
      'lib/pages/javbus/javbus_thread_page.dart',
      'lib/widgets/common/external_link_confirm_dialog.dart',
    ];

    const disallowedColors = [
      'Colors.red',
      'Colors.orange',
      'Colors.green',
      'Colors.grey',
      'Colors.black',
      'Colors.white',
      'Colors.black87',
      'Colors.white70',
    ];

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      for (final color in disallowedColors) {
        expect(source, isNot(contains(color)), reason: '$path contains $color');
      }
    }
  });
}
