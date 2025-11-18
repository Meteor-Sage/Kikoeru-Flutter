import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Triggers when Settings screen should refresh cache-related information.
final settingsCacheRefreshTriggerProvider = StateProvider<int>((ref) => 0);

/// Triggers when Subtitle Library screen should refresh (e.g., after path change).
final subtitleLibraryRefreshTriggerProvider = StateProvider<int>((ref) => 0);

/// 字幕库匹配优先级
enum SubtitleLibraryPriority {
  /// 最优先 - 字幕库优先于文件树匹配
  highest('优先', 'highest'),

  /// 最后 - 字幕库在文件树匹配之后
  lowest('滞后', 'lowest');

  final String displayName;
  final String value;
  const SubtitleLibraryPriority(this.displayName, this.value);
}

/// 字幕库优先级设置
class SubtitleLibraryPriorityNotifier
    extends StateNotifier<SubtitleLibraryPriority> {
  static const String _preferenceKey = 'subtitle_library_priority';

  SubtitleLibraryPriorityNotifier() : super(SubtitleLibraryPriority.highest) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedValue = prefs.getString(_preferenceKey);

      if (savedValue != null) {
        final priority = SubtitleLibraryPriority.values.firstWhere(
          (p) => p.value == savedValue,
          orElse: () => SubtitleLibraryPriority.highest,
        );
        state = priority;
      }
    } catch (e) {
      // 加载失败，使用默认值
      state = SubtitleLibraryPriority.highest;
    }
  }

  Future<void> updatePriority(SubtitleLibraryPriority priority) async {
    state = priority;
    await _savePreference();
  }

  Future<void> _savePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_preferenceKey, state.value);
    } catch (e) {
      // 保存失败时静默处理
    }
  }
}

/// 字幕库优先级提供者
final subtitleLibraryPriorityProvider = StateNotifierProvider<
    SubtitleLibraryPriorityNotifier, SubtitleLibraryPriority>((ref) {
  return SubtitleLibraryPriorityNotifier();
});

/// 音频格式类型
enum AudioFormat {
  mp3('MP3', 'mp3'),
  flac('FLAC', 'flac'),
  wav('WAV', 'wav'),
  opus('Opus', 'opus'),
  m4a('M4A', 'm4a'),
  aac('AAC', 'aac');

  final String displayName;
  final String extension;
  const AudioFormat(this.displayName, this.extension);
}

/// 音频格式优先级设置
class AudioFormatPreference {
  final List<AudioFormat> priority;

  const AudioFormatPreference({
    this.priority = const [
      AudioFormat.mp3,
      AudioFormat.flac,
      AudioFormat.wav,
      AudioFormat.opus,
      AudioFormat.m4a,
      AudioFormat.aac,
    ],
  });

  AudioFormatPreference copyWith({List<AudioFormat>? priority}) {
    return AudioFormatPreference(
      priority: priority ?? this.priority,
    );
  }
}

/// 音频格式优先级控制器
class AudioFormatPreferenceNotifier
    extends StateNotifier<AudioFormatPreference> {
  static const String _preferenceKey = 'audio_format_preference';

  AudioFormatPreferenceNotifier() : super(const AudioFormatPreference()) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedOrder = prefs.getStringList(_preferenceKey);

      if (savedOrder != null && savedOrder.isNotEmpty) {
        final priority = savedOrder
            .map((ext) => AudioFormat.values.firstWhere(
                  (format) => format.extension == ext,
                  orElse: () => AudioFormat.mp3,
                ))
            .toList();

        // 确保所有格式都存在
        for (final format in AudioFormat.values) {
          if (!priority.contains(format)) {
            priority.add(format);
          }
        }

        state = AudioFormatPreference(priority: priority);
      }
    } catch (e) {
      // 加载失败，使用默认值
      state = const AudioFormatPreference();
    }
  }

  Future<void> updatePriority(List<AudioFormat> newPriority) async {
    state = state.copyWith(priority: newPriority);
    await _savePreference();
  }

  Future<void> _savePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final order = state.priority.map((format) => format.extension).toList();
      await prefs.setStringList(_preferenceKey, order);
    } catch (e) {
      // 保存失败时静默处理
    }
  }

  Future<void> resetToDefault() async {
    state = const AudioFormatPreference();
    await _savePreference();
  }
}

/// 音频格式优先级提供者
final audioFormatPreferenceProvider =
    StateNotifierProvider<AudioFormatPreferenceNotifier, AudioFormatPreference>(
        (ref) {
  return AudioFormatPreferenceNotifier();
});

/// 防社死设置
class PrivacyModeSettings {
  final bool enabled;
  final bool blurCover;
  final bool maskTitle;
  final String customTitle;

  const PrivacyModeSettings({
    this.enabled = false,
    this.blurCover = true,
    this.maskTitle = false,
    this.customTitle = '正在播放音频',
  });

  PrivacyModeSettings copyWith({
    bool? enabled,
    bool? blurCover,
    bool? maskTitle,
    String? customTitle,
  }) {
    return PrivacyModeSettings(
      enabled: enabled ?? this.enabled,
      blurCover: blurCover ?? this.blurCover,
      maskTitle: maskTitle ?? this.maskTitle,
      customTitle: customTitle ?? this.customTitle,
    );
  }
}

/// 防社死设置控制器
class PrivacyModeSettingsNotifier extends StateNotifier<PrivacyModeSettings> {
  static const String _enabledKey = 'privacy_mode_enabled';
  static const String _blurCoverKey = 'privacy_mode_blur_cover';
  static const String _maskTitleKey = 'privacy_mode_mask_title';
  static const String _customTitleKey = 'privacy_mode_custom_title';

  PrivacyModeSettingsNotifier() : super(const PrivacyModeSettings()) {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = PrivacyModeSettings(
        enabled: prefs.getBool(_enabledKey) ?? false,
        blurCover: prefs.getBool(_blurCoverKey) ?? true,
        maskTitle: prefs.getBool(_maskTitleKey) ?? false,
        customTitle: prefs.getString(_customTitleKey) ?? '正在播放音频',
      );
    } catch (e) {
      // 加载失败，使用默认值
      state = const PrivacyModeSettings();
    }
  }

  Future<void> setEnabled(bool enabled) async {
    state = state.copyWith(enabled: enabled);
    await _savePreference(_enabledKey, enabled);
  }

  Future<void> setBlurCover(bool blur) async {
    state = state.copyWith(blurCover: blur);
    await _savePreference(_blurCoverKey, blur);
  }

  Future<void> setMaskTitle(bool mask) async {
    state = state.copyWith(maskTitle: mask);
    await _savePreference(_maskTitleKey, mask);
  }

  Future<void> setCustomTitle(String title) async {
    state = state.copyWith(customTitle: title);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customTitleKey, title);
  }

  Future<void> _savePreference(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      // 保存失败时静默处理
    }
  }
}

/// 防社死设置提供者
final privacyModeSettingsProvider =
    StateNotifierProvider<PrivacyModeSettingsNotifier, PrivacyModeSettings>(
        (ref) {
  return PrivacyModeSettingsNotifier();
});
