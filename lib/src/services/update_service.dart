import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to check for app updates from GitHub releases
class UpdateService {
  static const String _githubApiUrl =
      'https://api.github.com/repos/Meteor-Sage/KikoFlu/releases/latest';
  static const String _releasePageUrl =
      'https://github.com/Meteor-Sage/KikoFlu/releases/latest';

  static const String _keyLastCheckedVersion = 'last_checked_version';
  static const String _keyLastNotifiedVersion = 'last_notified_version';
  static const String _keyLastCheckTime = 'last_check_time';

  final Dio _dio;

  UpdateService({Dio? dio}) : _dio = dio ?? Dio();

  /// Check for updates silently (no user feedback on failure)
  /// Returns update info if a new version is available, null otherwise
  Future<UpdateInfo?> checkForUpdates({bool force = false}) async {
    try {
      // Get current version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // Check if we should skip the check (recently checked)
      if (!force) {
        final prefs = await SharedPreferences.getInstance();
        final lastCheckTime = prefs.getInt(_keyLastCheckTime) ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        // Skip if checked within last hour
        if (now - lastCheckTime < 3600000) {
          final lastCheckedVersion = prefs.getString(_keyLastCheckedVersion);
          if (lastCheckedVersion != null &&
              lastCheckedVersion != currentVersion) {
            return UpdateInfo(
              latestVersion: lastCheckedVersion,
              currentVersion: currentVersion,
              releaseUrl: _releasePageUrl,
              hasNewVersion: true,
            );
          }
          return null;
        }
      }

      // Make API request with timeout
      final response = await _dio.get(
        _githubApiUrl,
        options: Options(
          headers: {
            'Accept': 'application/vnd.github.v3+json',
          },
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final tagName = data['tag_name'] as String? ?? '';

        // Extract version from tag_name (remove 'v' prefix and anything after '(')
        // Examples: 'v1.0.6' -> '1.0.6', 'v1.0.6(1024)' -> '1.0.6', '1.0.6' -> '1.0.6'
        String latestVersion = tagName
            .replaceFirst('v', '')
            .replaceFirst(RegExp(r'\(.*\)'), '')
            .trim();

        if (latestVersion.isEmpty) {
          return null;
        }

        // Save check time and version
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyLastCheckedVersion, latestVersion);
        await prefs.setInt(
            _keyLastCheckTime, DateTime.now().millisecondsSinceEpoch);

        // Compare versions
        final hasNewVersion =
            _compareVersions(currentVersion, latestVersion) < 0;

        return UpdateInfo(
          latestVersion: latestVersion,
          currentVersion: currentVersion,
          releaseUrl: _releasePageUrl,
          hasNewVersion: hasNewVersion,
        );
      }
    } catch (e) {
      // Silent failure - no user notification
      // Could log for debugging purposes if needed
    }
    return null;
  }

  /// Check if the red dot should be shown for the current latest version
  /// Returns true if a new version exists and hasn't been notified yet
  Future<bool> shouldShowRedDot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheckedVersion = prefs.getString(_keyLastCheckedVersion);
      final lastNotifiedVersion = prefs.getString(_keyLastNotifiedVersion);

      if (lastCheckedVersion == null || lastCheckedVersion.isEmpty) {
        return false;
      }

      // Get current version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // Show red dot if there's a new version and it hasn't been notified
      return _compareVersions(currentVersion, lastCheckedVersion) < 0 &&
          lastCheckedVersion != lastNotifiedVersion;
    } catch (e) {
      return false;
    }
  }

  /// Mark the current new version as notified (hide red dot)
  Future<void> markAsNotified() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheckedVersion = prefs.getString(_keyLastCheckedVersion);
      if (lastCheckedVersion != null) {
        await prefs.setString(_keyLastNotifiedVersion, lastCheckedVersion);
      }
    } catch (e) {
      // Silent failure
    }
  }

  /// Compare two version strings
  /// Returns: -1 if v1 < v2, 0 if equal, 1 if v1 > v2
  int _compareVersions(String v1, String v2) {
    final parts1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final parts2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final maxLength =
        parts1.length > parts2.length ? parts1.length : parts2.length;

    for (int i = 0; i < maxLength; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;

      if (p1 < p2) return -1;
      if (p1 > p2) return 1;
    }

    return 0;
  }

  /// Clear all update check data
  Future<void> clearUpdateData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyLastCheckedVersion);
      await prefs.remove(_keyLastNotifiedVersion);
      await prefs.remove(_keyLastCheckTime);
    } catch (e) {
      // Silent failure
    }
  }
}

/// Information about available updates
class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String releaseUrl;
  final bool hasNewVersion;

  const UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.releaseUrl,
    required this.hasNewVersion,
  });

  @override
  String toString() {
    return 'UpdateInfo(latest: $latestVersion, current: $currentVersion, hasNew: $hasNewVersion)';
  }
}
