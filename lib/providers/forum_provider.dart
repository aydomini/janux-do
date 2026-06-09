import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../forum_adapter/adapter.dart';
import '../forum_adapter/javbus/javbus_adapter.dart';
import '../forum_adapter/models/forum_forum.dart';
import '../forum_adapter/models/forum_results.dart';

final forumAdapterProvider = Provider<ForumAdapter>((ref) {
  return JavbusAdapter();
});

final forumListProvider = FutureProvider<List<ForumForum>>((ref) async {
  return ref.watch(forumAdapterProvider).getForums();
});

