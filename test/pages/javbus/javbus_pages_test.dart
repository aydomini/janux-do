import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/forum_adapter/adapter.dart';
import 'package:fluxdo/forum_adapter/exceptions.dart';
import 'package:fluxdo/forum_adapter/models/forum_attachment.dart';
import 'package:fluxdo/forum_adapter/models/forum_forum.dart';
import 'package:fluxdo/forum_adapter/models/forum_post.dart';
import 'package:fluxdo/forum_adapter/models/forum_results.dart';
import 'package:fluxdo/forum_adapter/models/forum_thread.dart';
import 'package:fluxdo/l10n/slang/strings.g.dart';
import 'package:fluxdo/pages/javbus/javbus_forum_page.dart';
import 'package:fluxdo/pages/javbus/javbus_home_page.dart';
import 'package:fluxdo/pages/javbus/javbus_layout.dart';
import 'package:fluxdo/pages/javbus/javbus_shell_page.dart';
import 'package:fluxdo/pages/javbus/javbus_thread_page.dart';
import 'package:fluxdo/providers/forum_provider.dart';
import 'package:fluxdo/services/javbus_cache_manager.dart';

class _FakeForumAdapter extends ForumAdapter {
  _FakeForumAdapter({
    this.forumsError,
    this.threadsError,
    this.postsError,
    this.threadsPerPage = 1,
    this.postsPerPage = 1,
    this.totalPostPages = 1,
    this.repeatedPostIds = false,
    this.repeatedFloorNumbers = false,
    this.includeImagePost = false,
    this.includeEmojiPost = false,
    this.includeCodePost = false,
    this.stalePostCurrentPage = false,
  });

  final Object? forumsError;
  final Object? threadsError;
  final Object? postsError;
  final int threadsPerPage;
  final int postsPerPage;
  final int totalPostPages;
  final bool repeatedPostIds;
  final bool repeatedFloorNumbers;
  final bool includeImagePost;
  final bool includeEmojiPost;
  final bool includeCodePost;
  final bool stalePostCurrentPage;
  final requestedThreadPages = <int>[];
  final requestedFilterTypeIds = <int?>[];
  final requestedPostPages = <int>[];

  @override
  Future<List<ForumForum>> getForums() async {
    final error = forumsError;
    if (error != null) {
      throw error;
    }
    return [
      ForumForum(
        forumId: 2,
        name: '有码讨论',
        description: '有码作品讨论区',
        threadCount: 120,
        todayPostCount: 5,
      ),
      const ForumForum(
        forumId: 2,
        name: '日本AV',
        description: '討論交流日本AV影片、日本女優、寫真女星。',
        filterTypeId: 8,
      ),
    ];
  }

  @override
  Future<ThreadListResult> getThreads({
    required int forumId,
    int? filterTypeId,
    int page = 1,
  }) async {
    final error = threadsError;
    if (error != null) {
      throw error;
    }
    requestedThreadPages.add(page);
    requestedFilterTypeIds.add(filterTypeId);
    return ThreadListResult(
      threads: List.generate(threadsPerPage, (index) {
        return ForumThread(
          threadId: 1000 + page * 100 + index,
          forumId: forumId,
          title: threadsPerPage == 1
              ? '普通主题 P$page'
              : '普通主题 P$page-${index + 1}',
          author: '楼主',
          replies: 3,
          views: 88,
          createdAt: DateTime(2026, 6, 7, 9, page),
          isPinned: index == 0,
          hasAttachment: true,
          lastReplyAt: DateTime(2026, 6, 8, 12),
        );
      }),
      currentPage: page,
      totalPages: 2,
      hasNextPage: page < 2,
    );
  }

  @override
  Future<PostListResult> getPosts({required int threadId, int page = 1}) async {
    final error = postsError;
    if (error != null) {
      throw error;
    }
    requestedPostPages.add(page);
    return PostListResult(
      posts: List.generate(postsPerPage, (index) {
        return ForumPost(
          postId: repeatedPostIds ? 500 + index : 500 + page * 100 + index,
          threadId: threadId,
          floorNumber: repeatedFloorNumbers
              ? index + 1
              : (page - 1) * postsPerPage + index + 1,
          authorId: page == 1 && index == 0 ? 9001 : 9002 + index,
          author: index == 0 && page == 1 ? '楼主' : '回复者$index',
          avatarUrl: 'https://www.javbus.com/forum/avatar-$index.jpg',
          contentHtml: _postContentHtml(index: index, page: page),
          attachments: index == 0 && page == 1
              ? const [
                  ForumAttachment(
                    attachmentId: 'abc',
                    fileName: '附件.txt',
                    url:
                        'https://www.javbus.com/forum/forum.php?mod=attachment&aid=abc',
                  ),
                ]
              : const [],
          isThreadAuthor: index == 0 && page == 1,
          createdAt: DateTime(2026, 6, 8, 11),
        );
      }),
      currentPage: stalePostCurrentPage ? 1 : page,
      totalPages: totalPostPages,
      hasNextPage: page < totalPostPages,
      threadTitle: '普通主题',
    );
  }

  String _postContentHtml({required int index, required int page}) {
    if (includeImagePost && index == 0 && page == 1) {
      return '<p>正文内容</p><img src="https://forum.javcdn.cc/i.imgur.com/Ts9d6xp.jpeg" />';
    }
    if (includeEmojiPost && index == 0 && page == 1) {
      return '<p>正文内容<img class="vm" '
          'src="static/image/smiley/default/huffy.gif" '
          'smilieid="11" alt=":huffy:" />后续文字</p>';
    }
    if (includeCodePost && index == 0 && page == 1) {
      return '<p>普通正文 <code>inlineCode()</code></p>'
          '<pre><code class="language-dart">final count = 1;\nprint(count);</code></pre>'
          '<blockquote><p>引用内容 <code>quoteCode</code></p></blockquote>';
    }
    return postsPerPage == 1
        ? '<p>正文内容 <strong>重点</strong></p>'
        : '<p>主题回复 P$page-${index + 1}</p>';
  }
}

Widget _testApp(Widget child, {ForumAdapter? adapter}) {
  return ProviderScope(
    overrides: [
      forumAdapterProvider.overrideWithValue(adapter ?? _FakeForumAdapter()),
    ],
    child: TranslationProvider(
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocaleUtils.supportedLocales,
        home: child,
      ),
    ),
  );
}

void main() {
  Future<void> useDesktopSurface(WidgetTester tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1440, 900));
  }

  test('JavBus 桌面布局尺寸与 FluxDO 两栏体验保持收敛', () {
    expect(JavBusLayout.compactBreakpoint, 860);
    expect(JavBusLayout.sidebarWidth, 288);
    expect(JavBusLayout.contentMaxWidth, 920);
    expect(JavBusLayout.postMetaColumnWidth, 112);
    expect(JavBusLayout.topicReplyColumnWidth, 84);
    expect(JavBusLayout.topicTimeColumnWidth, 132);
    expect(JavBusLayout.mediaPreviewMaxWidth, 460);
    expect(JavBusLayout.mediaPreviewHeight, 300);
  });

  testWidgets('JavBus 首页使用桌面双栏展示分区和帖子列表', (tester) async {
    await useDesktopSurface(tester);
    await tester.pumpWidget(_testApp(const JavBusHomePage()));
    await tester.pumpAndSettle();

    expect(find.byType(JavBusShellPage), findsOneWidget);
    expect(find.text('JANUX DO'), findsOneWidget);
    expect(find.text('分区'), findsOneWidget);
    expect(find.text('有码讨论'), findsWidgets);
    expect(find.text('日本AV'), findsOneWidget);
    expect(find.textContaining('120 主题'), findsOneWidget);
    expect(find.text('普通主题 P1'), findsOneWidget);
    expect(find.textContaining('天前'), findsOneWidget);
    expect(find.text('话题'), findsOneWidget);
    expect(find.text('回复'), findsOneWidget);
    expect(find.text('时间'), findsOneWidget);
    expect(find.byType(JavBusForumPage), findsNothing);
  });

  testWidgets('JavBus 首页切换分类时保留 typeid 筛选', (tester) async {
    await useDesktopSurface(tester);
    final adapter = _FakeForumAdapter();
    await tester.pumpWidget(_testApp(const JavBusHomePage(), adapter: adapter));
    await tester.pumpAndSettle();

    await tester.tap(find.text('日本AV'));
    await tester.pumpAndSettle();

    expect(find.byType(JavBusShellPage), findsOneWidget);
    expect(find.byType(JavBusForumPage), findsNothing);
    expect(adapter.requestedFilterTypeIds, contains(8));
  });

  testWidgets('JavBus 首页切换分区后返回时保留帖子列表缓存', (tester) async {
    await useDesktopSurface(tester);
    final adapter = _FakeForumAdapter();
    await tester.pumpWidget(_testApp(const JavBusHomePage(), adapter: adapter));
    await tester.pumpAndSettle();

    expect(adapter.requestedFilterTypeIds, [null]);

    await tester.tap(find.text('日本AV'));
    await tester.pumpAndSettle();

    expect(adapter.requestedFilterTypeIds, [null, 8]);

    await tester.tap(find.text('有码讨论').first);
    await tester.pumpAndSettle();

    expect(find.text('普通主题 P1'), findsOneWidget);
    expect(adapter.requestedFilterTypeIds, [null, 8]);
  });

  testWidgets('JavBus 首页点击帖子后在右侧区域切换为详情', (tester) async {
    await useDesktopSurface(tester);
    await tester.pumpWidget(_testApp(const JavBusHomePage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('普通主题 P1'));
    await tester.pumpAndSettle();

    expect(find.byType(JavBusShellPage), findsOneWidget);
    expect(find.byType(JavBusThreadPage), findsNothing);
    expect(find.text('普通主题 P1'), findsOneWidget);
    expect(find.textContaining('已加载'), findsNothing);
    expect(find.textContaining('正文内容', findRichText: true), findsOneWidget);
    expect(find.textContaining('重点', findRichText: true), findsOneWidget);
    expect(find.textContaining('#1'), findsOneWidget);
    expect(find.text('附件.txt'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.textContaining('正文内容', findRichText: true),
        matching: find.byType(SelectionArea),
      ),
      findsOneWidget,
    );
  });

  testWidgets('JavBus 首页从详情返回时保留帖子列表状态且不重新请求第一页', (tester) async {
    await useDesktopSurface(tester);
    final adapter = _FakeForumAdapter();
    await tester.pumpWidget(_testApp(const JavBusHomePage(), adapter: adapter));
    await tester.pumpAndSettle();

    expect(adapter.requestedThreadPages, [1]);

    await tester.tap(find.text('普通主题 P1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回话题列表'));
    await tester.pumpAndSettle();

    expect(find.text('普通主题 P1'), findsOneWidget);
    expect(adapter.requestedThreadPages, [1]);
  });

  testWidgets('JavBus 首页重新进入同一主题时保留详情缓存', (tester) async {
    await useDesktopSurface(tester);
    final adapter = _FakeForumAdapter(postsPerPage: 20, totalPostPages: 2);
    await tester.pumpWidget(_testApp(const JavBusHomePage(), adapter: adapter));
    await tester.pumpAndSettle();

    await tester.tap(find.text('普通主题 P1'));
    await tester.pumpAndSettle();

    await tester.fling(
      find.byType(ListView).last,
      const Offset(0, -2200),
      3000,
    );
    await tester.pumpAndSettle();

    expect(adapter.requestedPostPages, [1, 2]);

    await tester.tap(find.byTooltip('返回话题列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('普通主题 P1'));
    await tester.pumpAndSettle();

    expect(find.textContaining('主题回复 P2-', findRichText: true), findsWidgets);
    expect(adapter.requestedPostPages, [1, 2]);
  });

  testWidgets('JavBus 首页展示错误态', (tester) async {
    await tester.pumpWidget(
      _testApp(
        const JavBusHomePage(),
        adapter: _FakeForumAdapter(
          forumsError: const ForumNetworkException('测试网络失败'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('JANUX DO 加载失败'), findsOneWidget);
    expect(find.text('测试网络失败'), findsOneWidget);
  });

  testWidgets('JavBus 版块页展示帖子并可进入主题页', (tester) async {
    await tester.pumpWidget(
      _testApp(const JavBusForumPage(forumId: 2, forumName: '有码讨论')),
    );
    await tester.pumpAndSettle();

    expect(find.text('普通主题 P1'), findsOneWidget);
    expect(find.text('置顶'), findsOneWidget);
    expect(find.text('3 回复'), findsOneWidget);
    expect(find.text('88 浏览'), findsNothing);

    await tester.tap(find.text('普通主题 P1'));
    await tester.pumpAndSettle();

    expect(find.byType(JavBusThreadPage), findsOneWidget);
    expect(find.textContaining('正文内容', findRichText: true), findsOneWidget);
  });

  testWidgets('JavBus 版块页滚动到底部后自动加载下一页', (tester) async {
    final adapter = _FakeForumAdapter(threadsPerPage: 20);
    await tester.pumpWidget(
      _testApp(
        const JavBusForumPage(forumId: 2, forumName: '有码讨论'),
        adapter: adapter,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('普通主题 P1-1'), findsOneWidget);
    expect(find.text('下一页'), findsNothing);

    await tester.fling(find.byType(ListView), const Offset(0, -1800), 3000);
    await tester.pumpAndSettle();

    expect(adapter.requestedThreadPages, containsAllInOrder([1, 2]));
    expect(find.text('下一页'), findsNothing);
  });

  testWidgets('JavBus 版块页展示 Cloudflare 错误提示', (tester) async {
    await tester.pumpWidget(
      _testApp(
        const JavBusForumPage(forumId: 2, forumName: '有码讨论'),
        adapter: _FakeForumAdapter(
          threadsError: const CloudflareChallengeException('JavBus 返回验证页'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('帖子列表加载失败'), findsOneWidget);
    expect(find.text('JavBus 安全验证'), findsOneWidget);
    expect(find.textContaining('Cloudflare'), findsOneWidget);
  });

  testWidgets('JavBus 主题页展示楼层内容', (tester) async {
    await tester.pumpWidget(
      _testApp(const JavBusThreadPage(threadId: 1001, initialTitle: '普通主题')),
    );
    await tester.pumpAndSettle();

    expect(find.text('普通主题'), findsWidgets);
    expect(find.textContaining('#1'), findsOneWidget);
    expect(find.byKey(const ValueKey('javbus-post-meta-1')), findsOneWidget);
    expect(find.textContaining('2026'), findsOneWidget);
    expect(find.textContaining('已加载'), findsNothing);
    expect(find.text('楼主'), findsWidgets);
    expect(find.textContaining('正文内容', findRichText: true), findsOneWidget);
    expect(find.textContaining('重点', findRichText: true), findsOneWidget);
    expect(find.text('附件.txt'), findsOneWidget);
  });

  testWidgets('JavBus 主题页滚动到底部后自动加载后续回复且不显示分页按钮', (tester) async {
    final adapter = _FakeForumAdapter(postsPerPage: 20, totalPostPages: 2);
    await tester.pumpWidget(
      _testApp(
        const JavBusThreadPage(threadId: 1001, initialTitle: '普通主题'),
        adapter: adapter,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('主题回复 P1-1', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('上一页'), findsNothing);
    expect(find.text('下一页'), findsNothing);

    await tester.fling(find.byType(ListView), const Offset(0, -2200), 3000);
    await tester.pumpAndSettle();

    expect(adapter.requestedPostPages, containsAllInOrder([1, 2]));
    expect(find.textContaining('主题回复 P2-', findRichText: true), findsWidgets);
    expect(find.text('上一页'), findsNothing);
    expect(find.text('下一页'), findsNothing);
  });

  testWidgets('JavBus 主题页不会因解析页码未前进而重复请求同一页', (tester) async {
    final adapter = _FakeForumAdapter(
      postsPerPage: 20,
      totalPostPages: 3,
      stalePostCurrentPage: true,
    );
    await tester.pumpWidget(
      _testApp(
        const JavBusThreadPage(threadId: 1001, initialTitle: '普通主题'),
        adapter: adapter,
      ),
    );
    await tester.pumpAndSettle();

    await tester.fling(find.byType(ListView), const Offset(0, -2200), 3000);
    await tester.pumpAndSettle();
    await tester.fling(find.byType(ListView), const Offset(0, -2200), 3000);
    await tester.pumpAndSettle();

    expect(adapter.requestedPostPages, [1, 2, 3]);
    expect(adapter.requestedPostPages.where((page) => page == 2), hasLength(1));
  });

  testWidgets('JavBus 主题页合并重复楼层避免循环显示', (tester) async {
    final adapter = _FakeForumAdapter(
      postsPerPage: 5,
      totalPostPages: 2,
      repeatedPostIds: true,
    );
    await tester.pumpWidget(
      _testApp(
        const JavBusThreadPage(threadId: 1001, initialTitle: '普通主题'),
        adapter: adapter,
      ),
    );
    await tester.pumpAndSettle();

    await tester.fling(find.byType(ListView), const Offset(0, -2200), 3000);
    await tester.pumpAndSettle();

    expect(adapter.requestedPostPages, containsAllInOrder([1, 2]));
    expect(find.textContaining('主题回复 P2-', findRichText: true), findsNothing);
  });

  testWidgets('JavBus 主题页按加载顺序修正分页重复楼层号', (tester) async {
    final adapter = _FakeForumAdapter(
      postsPerPage: 5,
      totalPostPages: 2,
      repeatedFloorNumbers: true,
    );
    await tester.pumpWidget(
      _testApp(
        const JavBusThreadPage(threadId: 1001, initialTitle: '普通主题'),
        adapter: adapter,
      ),
    );
    await tester.pumpAndSettle();

    await tester.fling(find.byType(ListView), const Offset(0, -2200), 3000);
    await tester.pumpAndSettle();

    expect(adapter.requestedPostPages, containsAllInOrder([1, 2]));
    expect(find.textContaining('#10'), findsOneWidget);
    expect(find.text('#5'), findsNothing);
  });

  testWidgets('JavBus 主题页使用固定预览尺寸渲染帖子图片', (tester) async {
    await tester.pumpWidget(
      _testApp(
        const JavBusThreadPage(threadId: 1001, initialTitle: '图片主题'),
        adapter: _FakeForumAdapter(includeImagePost: true),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(JavBusPostImage), findsOneWidget);
    final image = tester.widget<JavBusPostImage>(find.byType(JavBusPostImage));
    expect(image.url, contains('forum.javcdn.cc'));
    expect(JavBusPostImage.httpHeaders['Referer'], 'https://www.javbus.com/');
    expect(JavBusPostImage.httpHeaders['User-Agent'], contains('Safari'));
    final previewNetworkImage = tester.widget<CachedNetworkImage>(
      find.descendant(
        of: find.byType(JavBusPostImage),
        matching: find.byType(CachedNetworkImage),
      ),
    );
    expect(
      previewNetworkImage.cacheManager,
      isA<JavBusPostImageCacheManager>(),
    );

    final imageSize = tester.getSize(find.byType(JavBusPostImage));
    expect(imageSize.height, JavBusLayout.mediaPreviewHeight + 16);
    expect(
      imageSize.width,
      inInclusiveRange(
        JavBusLayout.mediaPreviewMinWidth,
        JavBusLayout.mediaPreviewMaxWidth,
      ),
    );
  });

  testWidgets('JavBus 主题页点击帖子图片后使用应用内原图预览', (tester) async {
    await tester.pumpWidget(
      _testApp(
        const JavBusThreadPage(threadId: 1001, initialTitle: '图片主题'),
        adapter: _FakeForumAdapter(includeImagePost: true),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final image = tester.widget<JavBusPostImage>(find.byType(JavBusPostImage));
    await tester.tap(find.byType(JavBusPostImage));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(JavBusImagePreviewDialog), findsOneWidget);
    final dialog = tester.widget<JavBusImagePreviewDialog>(
      find.byType(JavBusImagePreviewDialog),
    );
    expect(dialog.url, image.url);
    expect(JavBusImagePreviewDialog.httpHeaders, JavBusPostImage.httpHeaders);
    final dialogNetworkImage = tester.widget<CachedNetworkImage>(
      find.descendant(
        of: find.byType(JavBusImagePreviewDialog),
        matching: find.byType(CachedNetworkImage),
      ),
    );
    expect(dialogNetworkImage.cacheManager, isA<JavBusPostImageCacheManager>());
  });

  testWidgets('JavBus 主题页内联渲染论坛表情且不使用大图预览框', (tester) async {
    await tester.pumpWidget(
      _testApp(
        const JavBusThreadPage(threadId: 1001, initialTitle: '表情主题'),
        adapter: _FakeForumAdapter(includeEmojiPost: true),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('正文内容', findRichText: true), findsOneWidget);
    expect(find.textContaining('后续文字', findRichText: true), findsOneWidget);
    expect(find.byType(JavBusPostImage), findsNothing);
    expect(find.byType(JavBusInlineEmojiImage), findsOneWidget);

    final emojiSize = tester.getSize(find.byType(JavBusInlineEmojiImage));
    expect(emojiSize.width, lessThanOrEqualTo(28));
    expect(emojiSize.height, lessThanOrEqualTo(28));
    final emojiNetworkImage = tester.widget<CachedNetworkImage>(
      find.descendant(
        of: find.byType(JavBusInlineEmojiImage),
        matching: find.byType(CachedNetworkImage),
      ),
    );
    expect(emojiNetworkImage.cacheManager, isA<JavBusEmojiCacheManager>());
  });

  testWidgets('JavBus 主题页用户头像使用专用头像缓存池', (tester) async {
    await tester.pumpWidget(
      _testApp(const JavBusThreadPage(threadId: 1001, initialTitle: '头像主题')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // _PostAvatar 内部使用 ClipOval + CachedNetworkImage
    final avatarImage = tester.widget<CachedNetworkImage>(
      find.descendant(
        of: find.byType(ClipOval),
        matching: find.byType(CachedNetworkImage),
      ),
    );
    expect(avatarImage.cacheManager, isA<JavBusAvatarCacheManager>());
  });

  testWidgets('JavBus 主题页统一渲染行内代码、代码块和引用块', (tester) async {
    await tester.pumpWidget(
      _testApp(
        const JavBusThreadPage(threadId: 1001, initialTitle: '代码主题'),
        adapter: _FakeForumAdapter(includeCodePost: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('普通正文', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('inlineCode()', findRichText: true),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('javbus-code-block')), findsOneWidget);
    final codeBlock = tester.widget<JavBusCodeBlock>(
      find.byType(JavBusCodeBlock),
    );
    expect(codeBlock.language, 'dart');
    expect(find.textContaining('final count = 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('javbus-quote-block')), findsOneWidget);
    expect(find.textContaining('引用内容', findRichText: true), findsOneWidget);
  });

  testWidgets('JavBus 主题页正文区域支持系统文本选择', (tester) async {
    await tester.pumpWidget(
      _testApp(const JavBusThreadPage(threadId: 1001, initialTitle: '普通主题')),
    );
    await tester.pumpAndSettle();

    final contentFinder = find.textContaining('正文内容', findRichText: true);
    expect(contentFinder, findsOneWidget);
    expect(
      find.ancestor(of: contentFinder, matching: find.byType(SelectionArea)),
      findsOneWidget,
    );
  });

  testWidgets('JavBus 主题页展示解析失败提示', (tester) async {
    await tester.pumpWidget(
      _testApp(
        const JavBusThreadPage(threadId: 1001, initialTitle: '普通主题'),
        adapter: _FakeForumAdapter(
          postsError: const ForumParseException(
            '未找到帖子楼层',
            parserName: 'ViewThreadParser',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('主题内容加载失败'), findsOneWidget);
    expect(find.text('JavBus 页面解析失败'), findsOneWidget);
    expect(find.text('未找到帖子楼层'), findsOneWidget);
  });
}
