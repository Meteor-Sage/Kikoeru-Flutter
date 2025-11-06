import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'src/screens/launcher_screen.dart';
import 'src/utils/theme.dart';
import 'src/services/storage_service.dart';
import 'src/services/account_database.dart';
import 'src/providers/audio_provider.dart';
import 'src/providers/video_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive for local storage
  await Hive.initFlutter();
  await StorageService.init();

  // Initialize account database
  await AccountDatabase.instance.database;

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

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
      ref.read(videoPlayerControllerProvider.notifier).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          title: 'Kikoeru',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme(lightDynamic),
          darkTheme: AppTheme.darkTheme(darkDynamic),
          themeMode: ThemeMode.system,
          home: const LauncherScreen(),
        );
      },
    );
  }
}
