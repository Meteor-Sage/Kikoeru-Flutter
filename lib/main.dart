import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'src/screens/launcher_screen.dart';
import 'src/utils/theme.dart';
import 'src/services/storage_service.dart';
import 'src/services/account_database.dart';
import 'src/services/cache_service.dart';
import 'src/services/download_service.dart';
import 'src/providers/audio_provider.dart';
import 'src/providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive for local storage
  await Hive.initFlutter();
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
          home: const LauncherScreen(),
        );
      },
    );
  }
}
