import 'dart:async';
import 'dart:io';

import 'package:catcher_2/catcher_2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'pages/javbus/javbus_home_page.dart';
import 'providers/locale_provider.dart';
import 'services/highlighter_service.dart';
import 'services/network/cookie/csrf_token_service.dart';
import 'services/network/cookie/cookie_jar_service.dart';
import 'services/data_management/cache_size_service.dart';
import 'services/favorites_service.dart';
import 'services/forum_cache_service.dart';
import 'services/search_cache_service.dart';
import 'services/thread_content_cache_service.dart';
import 'services/javbus_cache_manager.dart';
import 'l10n/s.dart';

import 'services/network/rhttp/rhttp_settings_service.dart';
import 'package:rhttp/rhttp.dart' as rhttp;
import 'services/connectivity_service.dart';
import 'services/log/json_file_handler.dart';
import 'services/log/log_writer.dart';
import 'services/log/logger_utils.dart';
import 'services/download_service.dart';
import 'services/migration_service.dart';
import 'services/navigation/app_route_observer.dart';
import 'services/navigation/navigator_key.dart';
import 'services/window_state_service.dart';
import 'services/windows_webview_environment_service.dart';
import 'constants.dart';
import 'utils/time_utils.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'providers/theme_provider.dart';
import 'theme/app_color_schemes.dart';
import 'theme/app_semantic_colors.dart';
import 'theme/app_typography.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'widgets/keyboard_shortcut_handler.dart';
import 'utils/platform_utils.dart';

const String appTitle = 'JANUX DO';

/// 初始化 rhttp Rust runtime
Future<bool> _initRhttp() async {
  await rhttp.Rhttp.init();
  return true;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 启用 Edge-to-Edge 模式（小白条沉浸式）
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // 初始化语法高亮服务（预热 Isolate Worker 和字体）
  HighlighterService.instance.initialize();


  // 阶段 1：并行执行所有不相互依赖的初始化
  final futures = <Future<dynamic>>[
    SharedPreferences.getInstance(),
    AppConstants.initUserAgent(),
    LogWriter.init(),
    if (Platform.isWindows)
      WindowsWebViewEnvironmentService.instance.initialize(),
    CookieJarService().initialize(),
    CsrfTokenService().init(),
    FavoritesService.instance.init(),
    ForumCacheService.instance.init(),
    SearchCacheService.instance.init(),
    ThreadContentCacheService.instance.init(),
    TimeUtils.initialize(),
  ];
  // 桌面平台初始化 window_manager 和 flutter_acrylic
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    futures.add(windowManager.ensureInitialized());
    futures.add(acrylic.Window.initialize());
  }
  final results = await Future.wait(futures);
  final prefs = results[0] as SharedPreferences;

  // 桌面平台：恢复窗口状态后再显示，避免默认位置闪烁
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await acrylic.Window.setEffect(
      effect: Platform.isMacOS
          ? acrylic.WindowEffect.sidebar
          : Platform.isWindows
          ? acrylic.WindowEffect.mica
          : acrylic.WindowEffect.disabled,
    );
    final isVisible = await windowManager.isVisible();
    await windowManager.setPreventClose(true);
    await windowManager.setTitle(appTitle);
    await windowManager.setMinimumSize(const Size(900, 640));
    WindowStateService.instance.startListening();
    if (isVisible) {
      await WindowStateService.instance.attach(prefs);
      if (Platform.isLinux) {
        await windowManager.focus();
      }
    } else {
      await windowManager.waitUntilReadyToShow(null, () async {
        await WindowStateService.instance.restore(prefs);
        if (Platform.isLinux) {
          await windowManager.focus();
        }
      });
    }
  }

  // 数据迁移
  await MigrationService.runAll(prefs);

  // 阶段 2：依赖 prefs 的初始化
  try {
    final rhttpInitResult = await Future.any([
      _initRhttp(),
      Future.delayed(const Duration(seconds: 5), () => false),
    ]);
    if (rhttpInitResult != true) {
      debugPrint('[rhttp] 初始化超时或失败');
      await RhttpSettingsService.instance.forceDisable();
    }
  } catch (e) {
    debugPrint('[rhttp] 初始化异常: $e');
    await RhttpSettingsService.instance.forceDisable();
  }

  try {
    await ConnectivityService.safeCheckConnectivity();
  } catch (e) {
    debugPrint('[Main] 初始连接状态同步失败: $e');
  }

  // 启动网络状态持续监听，macOS 重启后 WiFi 就绪时自动触发刷新
  ConnectivityService().init();

  // 初始化下载服务
  DownloadService().initialize();

  // 冷启动自动清除缓存（如果用户开启了该选项）
  if (prefs.getBool('pref_clear_cache_on_exit') == true) {
    Future.wait([
      JavBusPostImageCacheManager().emptyCache(),
      JavBusAvatarCacheManager().emptyCache(),
      JavBusEmojiCacheManager().emptyCache(),
    ]).then((_) => CacheSizeService.deleteImageCacheDirs()).ignore();
  }


  // 记录应用启动日志
  LogWriter.instance.write({
    'timestamp': DateTime.now().toIso8601String(),
    'level': 'info',
    'type': 'lifecycle',
    'event': 'app_start',
    'message': '应用启动',
  });

  // 清理过期日志（14 天前）
  LoggerUtils.cleanExpiredLogs().ignore();

  // 根据当前语言配置
  final savedLocale = prefs.getString('pref_locale');
  if (savedLocale != null && savedLocale != 'system') {
    await LocaleSettings.setLocaleRaw(savedLocale);
  } else {
    await LocaleSettings.useDeviceLocale();
  }

  // 过滤 Flutter 框架已知 bug
  bool filterKnownFrameworkBugs(Report report) {
    final error = report.error;
    if (error is AssertionError &&
        error.message?.toString().contains(
              'Drag target size is larger than scrollable size',
            ) ==
            true) {
      return false;
    }
    return true;
  }

  // 配置 Catcher2 全局异常捕获
  final debugConfig = Catcher2Options(
    SilentReportMode(),
    [ConsoleHandler(), JsonFileHandler()],
    handlerTimeout: 10000,
    filterFunction: filterKnownFrameworkBugs,
  );
  final releaseConfig = Catcher2Options(
    SilentReportMode(),
    [JsonFileHandler()],
    handlerTimeout: 10000,
    filterFunction: filterKnownFrameworkBugs,
  );

  Catcher2(
    navigatorKey: navigatorKey,
    rootWidget: ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MainApp(),
    ),
    debugConfig: debugConfig,
    releaseConfig: releaseConfig,
    profileConfig: releaseConfig,
    enableLogger: kDebugMode,
  );
}

class MainApp extends ConsumerWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    ref.listen<Locale?>(localeProvider, (_, next) {
      unawaited(_syncSlangLocale(next));
    });

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final rawDynamicPrimary = lightDynamic?.primary;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(themeProvider.notifier).setDynamicPrimary(rawDynamicPrimary);
        });

        final appSchemes = AppColorSchemes.resolve(
          useDynamicColor: themeState.useDynamicColor,
          lightDynamic: lightDynamic,
          darkDynamic: darkDynamic,
          seedColor: themeState.seedColor,
          schemeVariant: themeState.schemeVariant,
        );
        final lightScheme = appSchemes.light;
        final darkScheme = appSchemes.dark;

        return TranslationProvider(
          child: Builder(
            builder: (context) => MaterialApp(
              navigatorKey: navigatorKey,
              navigatorObservers: [appRouteObserver],
              title: appTitle,
              locale: TranslationProvider.of(context).flutterLocale,
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocaleUtils.supportedLocales,
              themeMode: themeState.mode,
              theme: ThemeData(
                colorScheme: lightScheme,
                extensions: [AppSemanticColors.fromColorScheme(lightScheme)],
                useMaterial3: true,
                fontFamily: themeState.fontFamilyName,
                textTheme: AppTypography.buildTextTheme(
                  fontFamily: themeState.fontFamilyName,
                ),
                cardTheme: CardThemeData(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  color: lightScheme.surfaceContainerLow,
                  margin: EdgeInsets.zero,
                ),
              ),
              darkTheme: ThemeData(
                colorScheme: darkScheme,
                extensions: [AppSemanticColors.fromColorScheme(darkScheme)],
                useMaterial3: true,
                fontFamily: themeState.fontFamilyName,
                textTheme: AppTypography.buildTextTheme(
                  fontFamily: themeState.fontFamilyName,
                ),
                cardTheme: CardThemeData(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  color: darkScheme.surfaceContainerLow,
                  margin: EdgeInsets.zero,
                ),
              ),
              builder: (context, child) {
                final brightness = Theme.of(context).brightness;
                final iconBrightness = brightness == Brightness.light
                    ? Brightness.dark
                    : Brightness.light;
                if (Platform.isMacOS ||
                    Platform.isWindows ||
                    Platform.isLinux) {
                  final isDark = brightness == Brightness.dark;
                  acrylic.Window.setEffect(
                    effect: Platform.isMacOS
                        ? acrylic.WindowEffect.sidebar
                        : Platform.isWindows
                        ? acrylic.WindowEffect.mica
                        : acrylic.WindowEffect.disabled,
                    dark: isDark,
                  );
                  if (Platform.isMacOS) {
                    acrylic.Window.overrideMacOSBrightness(dark: isDark);
                  }
                }
                Widget result = AnnotatedRegion<SystemUiOverlayStyle>(
                  value: SystemUiOverlayStyle(
                    statusBarColor: Colors.transparent,
                    statusBarIconBrightness: iconBrightness,
                    systemNavigationBarIconBrightness: iconBrightness,
                    systemNavigationBarColor: Colors.transparent,
                    systemNavigationBarDividerColor: Colors.transparent
                        .withAlpha(1),
                    systemNavigationBarContrastEnforced: false,
                  ),
                  child: child!,
                );

                // 桌面端：全局鼠标返回键 + 键盘快捷键
                if (PlatformUtils.isDesktop) {
                  result = Listener(
                    onPointerDown: (event) {
                      if (event.buttons & 0x08 != 0) {
                        navigatorKey.currentState?.maybePop();
                      }
                    },
                    child: KeyboardShortcutHandler(
                      navigatorKey: navigatorKey,
                      child: result,
                    ),
                  );
                }

                return result;
              },
              home: const JavBusHomePage(),
            ),
          ),
        );
      },
    );
  }
}

Future<void> _syncSlangLocale(Locale? locale) async {
  if (locale == null) {
    await LocaleSettings.useDeviceLocale();
    return;
  }

  final rawLocale = locale.countryCode?.isNotEmpty == true
      ? '${locale.languageCode}_${locale.countryCode}'
      : locale.languageCode;
  await LocaleSettings.setLocaleRaw(rawLocale);
}
