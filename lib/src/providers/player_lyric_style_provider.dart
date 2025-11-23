import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlayerLyricSettings {
  // Mini Player
  final double miniFontSize;
  final double miniLineHeight;

  // Small Player (Portrait below cover)
  final double smallFontSize;
  final double smallLineHeight;

  // Full Player (Portrait full / Landscape)
  final double fullActiveFontSize;
  final double fullInactiveFontSize;
  final double fullLineHeight;

  const PlayerLyricSettings({
    this.miniFontSize = 11.0,
    this.miniLineHeight = 1.0,
    this.smallFontSize = 14.0,
    this.smallLineHeight = 1.2,
    this.fullActiveFontSize = 18.0,
    this.fullInactiveFontSize = 16.0,
    this.fullLineHeight = 1.5,
  });

  PlayerLyricSettings copyWith({
    double? miniFontSize,
    double? miniLineHeight,
    double? smallFontSize,
    double? smallLineHeight,
    double? fullActiveFontSize,
    double? fullInactiveFontSize,
    double? fullLineHeight,
  }) {
    return PlayerLyricSettings(
      miniFontSize: miniFontSize ?? this.miniFontSize,
      miniLineHeight: miniLineHeight ?? this.miniLineHeight,
      smallFontSize: smallFontSize ?? this.smallFontSize,
      smallLineHeight: smallLineHeight ?? this.smallLineHeight,
      fullActiveFontSize: fullActiveFontSize ?? this.fullActiveFontSize,
      fullInactiveFontSize: fullInactiveFontSize ?? this.fullInactiveFontSize,
      fullLineHeight: fullLineHeight ?? this.fullLineHeight,
    );
  }
}

class PlayerLyricSettingsNotifier extends StateNotifier<PlayerLyricSettings> {
  static const _keyPrefix = 'player_lyric_';

  PlayerLyricSettingsNotifier() : super(const PlayerLyricSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    state = PlayerLyricSettings(
      miniFontSize: prefs.getDouble('${_keyPrefix}miniFontSize') ?? 11.0,
      miniLineHeight: prefs.getDouble('${_keyPrefix}miniLineHeight') ?? 1.0,
      smallFontSize: prefs.getDouble('${_keyPrefix}smallFontSize') ?? 14.0,
      smallLineHeight: prefs.getDouble('${_keyPrefix}smallLineHeight') ?? 1.2,
      fullActiveFontSize:
          prefs.getDouble('${_keyPrefix}fullActiveFontSize') ?? 18.0,
      fullInactiveFontSize:
          prefs.getDouble('${_keyPrefix}fullInactiveFontSize') ?? 16.0,
      fullLineHeight: prefs.getDouble('${_keyPrefix}fullLineHeight') ?? 1.5,
    );
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('${_keyPrefix}miniFontSize', state.miniFontSize);
    await prefs.setDouble('${_keyPrefix}miniLineHeight', state.miniLineHeight);
    await prefs.setDouble('${_keyPrefix}smallFontSize', state.smallFontSize);
    await prefs.setDouble(
        '${_keyPrefix}smallLineHeight', state.smallLineHeight);
    await prefs.setDouble(
        '${_keyPrefix}fullActiveFontSize', state.fullActiveFontSize);
    await prefs.setDouble(
        '${_keyPrefix}fullInactiveFontSize', state.fullInactiveFontSize);
    await prefs.setDouble('${_keyPrefix}fullLineHeight', state.fullLineHeight);
  }

  Future<void> updateMiniFontSize(double value) async {
    state = state.copyWith(miniFontSize: value);
    await _save();
  }

  Future<void> updateMiniLineHeight(double value) async {
    state = state.copyWith(miniLineHeight: value);
    await _save();
  }

  Future<void> updateSmallFontSize(double value) async {
    state = state.copyWith(smallFontSize: value);
    await _save();
  }

  Future<void> updateSmallLineHeight(double value) async {
    state = state.copyWith(smallLineHeight: value);
    await _save();
  }

  Future<void> updateFullActiveFontSize(double value) async {
    state = state.copyWith(fullActiveFontSize: value);
    await _save();
  }

  Future<void> updateFullInactiveFontSize(double value) async {
    state = state.copyWith(fullInactiveFontSize: value);
    await _save();
  }

  Future<void> updateFullLineHeight(double value) async {
    state = state.copyWith(fullLineHeight: value);
    await _save();
  }

  Future<void> reset() async {
    state = const PlayerLyricSettings();
    await _save();
  }
}

final playerLyricSettingsProvider =
    StateNotifierProvider<PlayerLyricSettingsNotifier, PlayerLyricSettings>(
        (ref) {
  return PlayerLyricSettingsNotifier();
});
