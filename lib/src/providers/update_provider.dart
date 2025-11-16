import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/update_service.dart';

/// Provider for the update service singleton
final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService();
});

/// Provider for update information
final updateInfoProvider = StateProvider<UpdateInfo?>((ref) => null);

/// Provider to track if red dot should be shown
final showUpdateRedDotProvider = StateProvider<bool>((ref) => false);

/// Provider to track if update check is in progress
final isCheckingUpdateProvider = StateProvider<bool>((ref) => false);
