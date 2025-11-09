import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class StorageService {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    // Initialize SharedPreferences
    _prefs = await SharedPreferences.getInstance();
  }

  // User data - using SharedPreferences with JSON encoding
  static Future<void> setUser(String key, dynamic value) async {
    if (value is Map<String, dynamic>) {
      await _prefs.setString(key, jsonEncode(value));
    } else {
      await _prefs.setString(key, jsonEncode(value));
    }
  }

  static T? getUser<T>(String key, {T? defaultValue}) {
    final jsonString = _prefs.getString(key);
    if (jsonString != null) {
      try {
        final decoded = jsonDecode(jsonString);
        return decoded as T?;
      } catch (e) {
        return defaultValue;
      }
    }
    return defaultValue;
  }

  static Future<void> removeUser(String key) async {
    await _prefs.remove(key);
  }

  static List<String> getAllUserKeys() {
    return _prefs.getKeys().toList();
  }

  // SharedPreferences methods
  static Future<void> setString(String key, String value) async {
    await _prefs.setString(key, value);
  }

  static String? getString(String key) {
    return _prefs.getString(key);
  }

  static Future<void> setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
  }

  static bool? getBool(String key) {
    return _prefs.getBool(key);
  }

  static Future<void> setInt(String key, int value) async {
    await _prefs.setInt(key, value);
  }

  static int? getInt(String key) {
    return _prefs.getInt(key);
  }

  static Future<void> remove(String key) async {
    await _prefs.remove(key);
  }

  static Future<void> clear() async {
    await _prefs.clear();
  }

  // JSON Map methods for complex objects
  static Future<void> setMap(String key, Map<String, dynamic> value) async {
    await _prefs.setString(key, jsonEncode(value));
  }

  static Map<String, dynamic>? getMap(String key) {
    final jsonString = _prefs.getString(key);
    if (jsonString != null) {
      try {
        return jsonDecode(jsonString) as Map<String, dynamic>;
      } catch (e) {
        print('Error decoding JSON for key $key: $e');
        return null;
      }
    }
    return null;
  }
}
