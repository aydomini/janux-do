import 'dart:math' as math;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../utils/url_builder.dart';

class PostHtmlCleaner {
  const PostHtmlCleaner({this.urlBuilder = const JavBusUrlBuilder()});

  final JavBusUrlBuilder urlBuilder;

  String clean(String rawHtml) {
    final withoutHidden = rawHtml
        .replaceAll(RegExp(r'\[hide\].*?\[/hide\]', dotAll: true), '')
        .replaceAll(RegExp(r'\[sell\].*?\[/sell\]', dotAll: true), '');
    final fragment = html_parser.parseFragment(withoutHidden);

    for (final element in fragment.querySelectorAll('[style], font[color]')) {
      _removeLowContrastTextColor(element);
    }

    for (final image in fragment.querySelectorAll('img')) {
      final file = _firstNonEmptyAttribute(image, [
        'file',
        'zoomfile',
        'data-original',
        'data-src',
      ]);
      if (file != null && file.isNotEmpty) {
        image.attributes['src'] = urlBuilder.resolve(file);
        image.attributes.remove('file');
        image.attributes.remove('zoomfile');
        image.attributes.remove('data-original');
        image.attributes.remove('data-src');
      } else {
        _resolveAttribute(image, 'src');
      }
    }

    for (final element in fragment.querySelectorAll('[href]')) {
      _resolveAttribute(element, 'href');
    }

    return fragment.nodes.map(_serializeNode).join();
  }

  static void _removeLowContrastTextColor(Element element) {
    final fontColor = _parseColor(element.attributes['color']);
    if (fontColor != null && _isLowContrastForumColor(fontColor)) {
      element.attributes.remove('color');
    }

    final style = element.attributes['style'];
    if (style == null || style.trim().isEmpty) return;

    final keptDeclarations = <String>[];
    for (final declaration in style.split(';')) {
      final trimmed = declaration.trim();
      if (trimmed.isEmpty) continue;

      final separatorIndex = trimmed.indexOf(':');
      if (separatorIndex <= 0) {
        keptDeclarations.add(trimmed);
        continue;
      }

      final property = trimmed
          .substring(0, separatorIndex)
          .trim()
          .toLowerCase();
      final value = trimmed.substring(separatorIndex + 1).trim();
      final parsedColor = property == 'color' ? _parseColor(value) : null;
      if (parsedColor != null && _isLowContrastForumColor(parsedColor)) {
        continue;
      }

      keptDeclarations.add(trimmed);
    }

    if (keptDeclarations.isEmpty) {
      element.attributes.remove('style');
      return;
    }
    element.attributes['style'] = keptDeclarations.join('; ');
  }

  static _RgbColor? _parseColor(String? rawValue) {
    if (rawValue == null) return null;
    final value = rawValue.trim().toLowerCase().replaceAll(
      RegExp(r'\s*!important\s*$'),
      '',
    );
    if (value.isEmpty) return null;

    const namedColors = <String, _RgbColor>{
      'black': _RgbColor(0, 0, 0),
      'navy': _RgbColor(0, 0, 128),
      'darkblue': _RgbColor(0, 0, 139),
      'darkgreen': _RgbColor(0, 100, 0),
      'darkred': _RgbColor(139, 0, 0),
      'maroon': _RgbColor(128, 0, 0),
    };
    final namedColor = namedColors[value];
    if (namedColor != null) return namedColor;

    final hexMatch = RegExp(r'^#([0-9a-f]{3}|[0-9a-f]{6})$').firstMatch(value);
    if (hexMatch != null) {
      final hex = hexMatch.group(1)!;
      if (hex.length == 3) {
        return _RgbColor(
          int.parse(hex[0] * 2, radix: 16),
          int.parse(hex[1] * 2, radix: 16),
          int.parse(hex[2] * 2, radix: 16),
        );
      }
      return _RgbColor(
        int.parse(hex.substring(0, 2), radix: 16),
        int.parse(hex.substring(2, 4), radix: 16),
        int.parse(hex.substring(4, 6), radix: 16),
      );
    }

    final rgbMatch = RegExp(
      r'^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})',
    ).firstMatch(value);
    if (rgbMatch == null) return null;

    return _RgbColor(
      int.parse(rgbMatch.group(1)!).clamp(0, 255).toInt(),
      int.parse(rgbMatch.group(2)!).clamp(0, 255).toInt(),
      int.parse(rgbMatch.group(3)!).clamp(0, 255).toInt(),
    );
  }

  static bool _isLowContrastForumColor(_RgbColor color) {
    if (color.relativeLuminance < 0.08) return true;
    return color.chroma <= 48 && color.relativeLuminance < 0.28;
  }

  void _resolveAttribute(Element element, String attribute) {
    final value = element.attributes[attribute]?.trim();
    if (value == null || value.isEmpty || value.startsWith('#')) return;
    element.attributes[attribute] = urlBuilder.resolve(value);
  }

  static String _serializeNode(Node node) {
    if (node is Element) return node.outerHtml;
    return node.text ?? '';
  }

  static String? _firstNonEmptyAttribute(
    Element element,
    List<String> attributes,
  ) {
    for (final attribute in attributes) {
      final value = element.attributes[attribute]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
}

class _RgbColor {
  const _RgbColor(this.red, this.green, this.blue);

  final int red;
  final int green;
  final int blue;

  int get chroma {
    final maxChannel = math.max(red, math.max(green, blue));
    final minChannel = math.min(red, math.min(green, blue));
    return maxChannel - minChannel;
  }

  double get relativeLuminance {
    final r = _linearize(red);
    final g = _linearize(green);
    final b = _linearize(blue);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  static double _linearize(int channel) {
    final normalized = channel / 255;
    if (normalized <= 0.04045) {
      return normalized / 12.92;
    }
    return math.pow((normalized + 0.055) / 1.055, 2.4).toDouble();
  }
}
