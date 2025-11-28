import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

import 'src/screens/login_screen.dart';
import 'src/screens/main_screen.dart';
import 'src/widgets/desktop_floating_lyric.dart';
import 'src/utils/theme.dart';
import 'src/services/storage_service.dart';
import 'src/services/account_database.dart';
import 'src/services/cache_service.dart';
import 'src/services/download_service.dart';
import 'src/services/floating_lyric_service.dart';
import 'src/providers/audio_provider.dart';
import 'src/providers/auth_provider.dart';
import 'src/providers/theme_provider.dart';
import 'src/providers/update_provider.dart';
import 'src/utils/global_keys.dart';

void _setEnv(String key, String value) {
  if (Platform.isWindows) {
    final keyNative = key.toNativeUtf16();
    final valueNative = value.toNativeUtf16();
    final SetEnvironmentVariable = ffi.DynamicLibrary.open('kernel32.dll')
        .lookupFunction<
            ffi.Int32 Function(ffi.Pointer<Utf16>, ffi.Pointer<Utf16>),
            int Function(ffi.Pointer<Utf16>,
                ffi.Pointer<Utf16>)>('SetEnvironmentVariableW');
    SetEnvironmentVariable(keyNative, valueNative);
    calloc.free(keyNative);
    calloc.free(valueNative);
  } else if (Platform.isMacOS) {
    final keyNative = key.toNativeUtf8();
    final valueNative = value.toNativeUtf8();
    final setenv = ffi.DynamicLibrary.process().lookupFunction<
        ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Int32),
        int Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, int)>('setenv');
    setenv(keyNative, valueNative, 1);
    calloc.free(keyNative);
    calloc.free(valueNative);
  }
}

Future<void> _configureMpv() async {
  if (!Platform.isWindows && !Platform.isMacOS) return;

  try {
    final prefs = await SharedPreferences.getInstance();
    final passthrough = prefs.getBool('audio_passthrough_enabled') ?? false;

    Directory configDir;
    if (Platform.isWindows) {
      final exePath = Platform.resolvedExecutable;
      final exeDir = p.dirname(exePath);
      configDir = Directory(p.join(exeDir, 'portable_config'));
    } else {
      final appSupportDir = await getApplicationSupportDirectory();
      configDir = Directory(p.join(appSupportDir.path, 'mpv_config'));
    }

    if (!await configDir.exists()) {
      await configDir.create(recursive: true);
    }

    final configFile = File(p.join(configDir.path, 'mpv.conf'));

    // Force set MPV_HOME to ensure config is read
    _setEnv('MPV_HOME', configDir.path);
    print('[Audio] Set MPV_HOME to: ${configDir.path}');

    if (passthrough) {
      String configContent;
      if (Platform.isWindows) {
        configContent = '''
ao=wasapi
audio-exclusive=yes
audio-spdif=ac3,dts,eac3
log-file=mpv_debug.log
msg-level=all=v
''';
      } else {
        configContent = '''
ao=coreaudio
audio-exclusive=yes
audio-spdif=ac3,dts,eac3
log-file=${p.join(configDir.path, 'mpv_debug.log')}
msg-level=all=v
''';
      }

      await configFile.writeAsString(configContent);
      print('[Audio] Updated mpv.conf: Exclusive Mode ENABLED (Forced)');
    } else {
      if (await configFile.exists()) {
        await configFile.delete();
        print('[Audio] Updated mpv.conf: Exclusive Mode DISABLED');
      }
    }
  } catch (e) {
    print('[Audio] Error configuring mpv: $e');
  }
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (args.firstOrNull == 'multi_window') {
    final windowId = args[1];
    final argument = args[2].isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(args[2]) as Map<String, dynamic>;

    // Initialize window manager for the new window
    await windowManager.ensureInitialized();

    runApp(DesktopFloatingLyric(
      windowId: windowId,
      arguments: argument,
    ));
    return;
  }

  // Initialize just_audio_media_kit for desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await _configureMpv();
    JustAudioMediaKit.ensureInitialized();
  }

  if (Platform.isWindows || Platform.isLinux) {
    // Initialize FFI
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Set minimum window size for desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(350, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
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
    print('[Cache] 启动时检查缓存失�? $e');
  });

  // 初始化下载服�?
  await DownloadService.instance.initialize();

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  // 允许横竖屏旋�?
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

class _KikoeruAppState extends ConsumerState<KikoeruApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.addListener(this);
    }
    // Initialize audio and video services
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(audioPlayerControllerProvider.notifier).initialize();

      // Silent update check on startup
      _checkForUpdates();
    });
  }

  @override
  void dispose() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (Platform.isWindows) {
      // 关闭主窗口时，同时关闭悬浮字幕窗�?
      await FloatingLyricService.instance.hide();
    }
    super.onWindowClose();
  }

  /// Silently check for updates on startup
  Future<void> _checkForUpdates() async {
    try {
      final updateService = ref.read(updateServiceProvider);
      final updateInfo = await updateService.checkForUpdates();

      if (updateInfo != null && updateInfo.hasNewVersion) {
        ref.read(updateInfoProvider.notifier).state = updateInfo;
        ref.read(hasNewVersionProvider.notifier).state = true;

        // Check if red dot should be shown
        final shouldShow = await updateService.shouldShowRedDot();
        ref.read(showUpdateRedDotProvider.notifier).state = shouldShow;
      }
    } catch (e) {
      // Silent failure - no user notification
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeSettings = ref.watch(themeSettingsProvider);

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        // 根据用户设置决定是否使用动态颜�?
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
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          title: 'Kikoeru',
          debugShowCheckedModeBanner: false,
          theme:
              AppTheme.lightTheme(lightScheme, themeSettings.colorSchemeType),
          darkTheme:
              AppTheme.darkTheme(darkScheme, themeSettings.colorSchemeType),
          themeMode: mode,
          home: _buildHomeScreen(),
        );
      },
    );
  }

  Widget _buildHomeScreen() {
    final authState = ref.watch(authProvider);

    // 如果有用户信息（包括离线模式），显示主页
    // 这样用户可以访问本地下载的内�?
    if (authState.currentUser != null) {
      return const MainScreen();
    } else {
      return const LoginScreen();
    }
  }
}
