class DiscuzTimeParser {
  DiscuzTimeParser({DateTime? now}) : now = now ?? DateTime.now();

  final DateTime now;

  DateTime? parse(String rawText) {
    final text = _normalize(rawText);
    if (text.isEmpty) return null;

    return _parseAbsolute(text) ??
        _parseDateOnly(text) ??
        _parseRelative(text) ??
        _parseNamedDay(text);
  }

  String _normalize(String rawText) {
    return rawText
        .replaceAll('\u00a0', ' ')
        .replaceAll('小時', '小时')
        .replaceAll('分鐘', '分钟')
        .replaceAll('發表於', '')
        .replaceAll('发表于', '')
        .replaceAll('发表於', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  DateTime? _parseAbsolute(String text) {
    final match = RegExp(
      r'(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})',
    ).firstMatch(text);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
    );
  }

  DateTime? _parseDateOnly(String text) {
    final match = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(text);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  DateTime? _parseRelative(String text) {
    // "半" 前缀：半小时前 → 30 分钟前
    final halfMatch = RegExp(r'半\s*(小时|天)前').firstMatch(text);
    if (halfMatch != null) {
      return switch (halfMatch.group(1)!) {
        '小时' => now.subtract(const Duration(minutes: 30)),
        '天' => now.subtract(const Duration(hours: 12)),
        _ => null,
      };
    }

    final match = RegExp(r'(\d+)\s*(分钟|小时|天)前').firstMatch(text);
    if (match == null) return null;
    final amount = int.parse(match.group(1)!);
    return switch (match.group(2)!) {
      '分钟' => now.subtract(Duration(minutes: amount)),
      '小时' => now.subtract(Duration(hours: amount)),
      '天' => now.subtract(Duration(days: amount)),
      _ => null,
    };
  }

  DateTime? _parseNamedDay(String text) {
    final match = RegExp(r'(昨天|前天)\s+(\d{1,2}):(\d{2})').firstMatch(text);
    if (match == null) return null;
    final days = match.group(1)! == '昨天' ? 1 : 2;
    final base = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days));
    return DateTime(
      base.year,
      base.month,
      base.day,
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }
}
