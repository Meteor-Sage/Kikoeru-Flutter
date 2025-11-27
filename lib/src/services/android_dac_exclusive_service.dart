import 'dart:io';

import 'package:flutter/services.dart';

/// Handles Android-specific DAC独占操作 via a method channel.
class AndroidDacExclusiveService {
  AndroidDacExclusiveService._();

  static final AndroidDacExclusiveService instance =
      AndroidDacExclusiveService._();

  static const MethodChannel _channel =
      MethodChannel('com.kikoeru.flutter/dac_exclusive');

  bool _isEnabled = false;
  bool? _isSupported;

  /// Checks whether the current Android device/OS supports DAC独占.
  Future<bool> isSupported() async {
    if (!Platform.isAndroid) {
      _isSupported = false;
      return false;
    }

    if (_isSupported != null) {
      return _isSupported!;
    }

    try {
      final supported =
          await _channel.invokeMethod<bool>('isSupported') ?? false;
      _isSupported = supported;
      return supported;
    } catch (_) {
      _isSupported = false;
      return false;
    }
  }

  /// Requests exclusive access. Returns whether the request succeeded.
  Future<bool> enable() async {
    if (!Platform.isAndroid) return false;

    final supported = await isSupported();
    if (!supported) {
      _isEnabled = false;
      return false;
    }

    try {
      _isEnabled = await _channel.invokeMethod<bool>('enable') ?? false;
      return _isEnabled;
    } catch (_) {
      _isEnabled = false;
      return false;
    }
  }

  /// Releases exclusive access if currently held.
  Future<void> disable() async {
    if (!Platform.isAndroid) return;
    if (!_isEnabled) return;

    try {
      await _channel.invokeMethod('disable');
    } catch (_) {
      // ignore
    } finally {
      _isEnabled = false;
    }
  }
}
