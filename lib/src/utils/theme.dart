import 'dart:io';
import 'package:flutter/material.dart';

class AppTheme {
  // Windows 平台的字体配置
  static TextTheme? _getTextTheme() {
    if (Platform.isWindows) {
      // 使用 Microsoft YaHei 作为主字体，确保中文显示一致
      const fontFamily = 'Microsoft YaHei';
      return const TextTheme(
        displayLarge:
            TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w400),
        displayMedium:
            TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w400),
        displaySmall:
            TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w400),
        headlineLarge:
            TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w400),
        headlineMedium:
            TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w400),
        headlineSmall:
            TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w400),
        titleLarge:
            TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w500),
        titleMedium:
            TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w500),
        titleSmall:
            TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w500),
        bodyLarge:
            TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w400),
        bodyMedium:
            TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w400),
        bodySmall:
            TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w400),
        labelLarge:
            TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w500),
        labelMedium:
            TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w500),
        labelSmall:
            TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w500),
      );
    }
    return null;
  }

  static ThemeData lightTheme(ColorScheme? lightDynamic) {
    final colorScheme = lightDynamic ?? _defaultLightColorScheme;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: _getTextTheme(),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      cardTheme: const CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurface,
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static ThemeData darkTheme(ColorScheme? darkDynamic) {
    final colorScheme = darkDynamic ?? _defaultDarkColorScheme;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: _getTextTheme(),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      cardTheme: const CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurface,
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static const _defaultLightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF146683),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFBFE9FF),
    onPrimaryContainer: Color(0xFF001F2A),
    secondary: Color(0xFF4D616C),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFD0E6F2),
    onSecondaryContainer: Color(0xFF081E27),
    tertiary: Color(0xFF5E5B7D),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFE4DFFF),
    onTertiaryContainer: Color(0xFF1A1836),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFFAFCFF),
    onSurface: Color(0xFF171C1F),
    surfaceDim: Color(0xFFFAFCFF),
    surfaceBright: Color(0xFFFAFCFF),
    surfaceContainerLowest: Color(0xFFFAFCFF),
    surfaceContainerLow: Color(0xFFFAFCFF),
    surfaceContainer: Color(0xFFFAFCFF),
    surfaceContainerHigh: Color(0xFFFAFCFF),
    surfaceContainerHighest: Color(0xFFFAFCFF),
    onSurfaceVariant: Color(0xFF40484C),
  );

  static const _defaultDarkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF8CCFF0),
    onPrimary: Color(0xFF003547),
    primaryContainer: Color(0xFF004D65),
    onPrimaryContainer: Color(0xFFBFE9FF),
    secondary: Color(0xFFB4CAD6),
    onSecondary: Color(0xFF1F333D),
    secondaryContainer: Color(0xFF364954),
    onSecondaryContainer: Color(0xFFD0E6F2),
    tertiary: Color(0xFFC7C2EA),
    onTertiary: Color(0xFF2F2D4C),
    tertiaryContainer: Color(0xFF464364),
    onTertiaryContainer: Color(0xFFE4DFFF),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFB4AB),
    surface: Color(0xFF171C1F),
    onSurface: Color(0xFFDFE3E7),
    surfaceDim: Color(0xFF171C1F),
    surfaceBright: Color(0xFF171C1F),
    surfaceContainerLowest: Color(0xFF171C1F),
    surfaceContainerLow: Color(0xFF171C1F),
    surfaceContainer: Color(0xFF171C1F),
    surfaceContainerHigh: Color(0xFF171C1F),
    surfaceContainerHighest: Color(0xFF171C1F),
    onSurfaceVariant: Color(0xFFC0C8CD),
  );
}
