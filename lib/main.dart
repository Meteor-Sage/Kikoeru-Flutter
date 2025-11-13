import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'src/screens/login_screen.dart';
import 'src/screens/main_screen.dart';
import 'src/utils/theme.dart';
import 'src/services/storage_service.dart';
import 'src/services/account_database.dart';
import 'src/services/cache_service.dart';
import 'src/services/download_service.dart';
import 'src/providers/audio_provider.dart';
import 'src/providers/auth_provider.dart';
import 'src/providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize just_audio_media_kit for platforms that require it
  if (Platform.isWindows || Platform.isLinux) {
    JustAudioMediaKit.ensureInitialized();
  } else if (Platform.isMacOS) {
    // macOS keeps the default just_audio backend until media_kit fixes completed events
    print('[Audio] Using default just_audio backend on macOS.');
  }

  // Initialize Hive for local storage
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // For desktop platforms, use application documents directory
    final appDocDir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter('${appDocDir.path}/KikoFlu');
  } else {
    // For mobile platforms, use default path
    await Hive.initFlutter();
  }
  await StorageService.init();

  // Initialize account database
  await AccountDatabase.instance.database;

  // 启动时检查并清理缓存（如果超过上限）
  CacheService.checkAndCleanCache(force: true).catchError((e) {
    print('[Cache] 启动时检查缓存失败: $e');
  });

  // 初始化下载服务
  await DownloadService.instance.initialize();

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  // 允许横竖屏旋转
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const ProviderScope(child: KikoeruApp()));
}

class KikoeruApp extends ConsumerStatefulWidget {
  const KikoeruApp({super.key});

  @override
  ConsumerState<KikoeruApp> createState() => _KikoeruAppState();
}

class _KikoeruAppState extends ConsumerState<KikoeruApp> {
  @override
  void initState() {
    super.initState();
    // Initialize audio and video services
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(audioPlayerControllerProvider.notifier).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeSettings = ref.watch(themeSettingsProvider);

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        // 根据用户设置决定是否使用动态颜色
        final ColorScheme? lightScheme =
            themeSettings.colorSchemeType == ColorSchemeType.dynamic
                ? lightDynamic
                : null;
        final ColorScheme? darkScheme =
            themeSettings.colorSchemeType == ColorSchemeType.dynamic
                ? darkDynamic
                : null;

        // 根据用户设置决定主题模式
        final ThemeMode mode = switch (themeSettings.themeMode) {
          AppThemeMode.system => ThemeMode.system,
          AppThemeMode.light => ThemeMode.light,
          AppThemeMode.dark => ThemeMode.dark,
        };

        return MaterialApp(
          title: 'Kikoeru',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme(lightScheme),
          darkTheme: AppTheme.darkTheme(darkScheme),
          themeMode: mode,
          home: _buildHomeScreen(),
        );
      },
    );
  }

  Widget _buildHomeScreen() {
    final authState = ref.watch(authProvider);

    if (authState.currentUser != null && authState.isLoggedIn) {
      return const MainScreen();
    } else {
      return const LoginScreen();
    }
  }
}
