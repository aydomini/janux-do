import 'dart:convert';
import 'dart:io' as io;

import 'package:path/path.dart' as path;

import 'canonical_cookie.dart';

class FileCookieStore {
  FileCookieStore(this.directoryPath);

  final String directoryPath;

  String get _filePath => path.join(directoryPath, 'cookies.v1.json');

  Future<List<CanonicalCookie>> readAll() async {
    final file = io.File(_filePath);
    if (!await file.exists()) return const [];
    try {
      final text = await file.readAsString();
      if (text.trim().isEmpty) return const [];
      final jsonValue = jsonDecode(text);
      if (jsonValue is! List) return const [];
      final cookies = <CanonicalCookie>[];
      for (final entry in jsonValue.whereType<Map>()) {
        try {
          cookies.add(CanonicalCookie.fromJson(Map<String, dynamic>.from(entry)));
        } catch (_) {
          // 跳过单个解析失败的 cookie，不影响其余
        }
      }
      return cookies;
    } catch (_) {
      // 文件损坏（JSON 截断等），返回空列表而非崩溃
      return const [];
    }
  }

  /// 原子写入：先写临时文件，再 rename 替换，避免写入中断导致文件损坏
  Future<void> writeAll(List<CanonicalCookie> cookies) async {
    final dir = io.Directory(directoryPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final payload = cookies.map((e) => e.toJson()).toList(growable: false);
    final content = jsonEncode(payload);

    final tmpFile = io.File('$_filePath.tmp');
    await tmpFile.writeAsString(content, flush: true);
    await tmpFile.rename(_filePath);
  }

  Future<void> deleteAll() async {
    final file = io.File(_filePath);
    if (await file.exists()) {
      await file.delete();
    }
    // 清理可能残留的临时文件
    final tmpFile = io.File('$_filePath.tmp');
    if (await tmpFile.exists()) {
      await tmpFile.delete();
    }
  }
}
