import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sort_options.dart';

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

/// 安卓 DAC 独占偏好
class AndroidExclusiveModeNotifier extends StateNotifier<bool> {
  static const String _preferenceKey = 'android_dac_exclusive_enabled';

  AndroidExclusiveModeNotifier() : super(false) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    if (!Platform.isAndroid) {
      state = false;
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_preferenceKey) ?? false;
    } catch (_) {
      state = false;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (!Platform.isAndroid) {
      state = false;
      return;
    }

    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_preferenceKey, enabled);
    } catch (_) {
      // ignore write failure
    }
  }
}

final androidExclusiveModeProvider =
    StateNotifierProvider<AndroidExclusiveModeNotifier, bool>((ref) {
  return AndroidExclusiveModeNotifier();
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

/// 翻译源
enum TranslationSource {
  google('Google 翻译', 'google'),
  youdao('Youdao 翻译', 'youdao'),
  microsoft('Microsoft 翻译', 'microsoft'),
  llm('LLM 翻译', 'llm');

  final String displayName;
  final String value;
  const TranslationSource(this.displayName, this.value);
}

class LLMSettings {
  final String apiUrl;
  final String apiKey;
  final String model;
  final String prompt;
  final int concurrency;

  const LLMSettings({
    this.apiUrl = 'https://api.openai.com/v1/chat/completions',
    this.apiKey = '',
    this.model = 'gpt-3.5-turbo',
    this.prompt =
        'You are a professional translator. Translate the following text into Simplified Chinese (zh-CN). Output ONLY the translated text without any explanations, notes, or markdown code blocks.',
    this.concurrency = 3,
  });

  LLMSettings copyWith({
    String? apiUrl,
    String? apiKey,
    String? model,
    String? prompt,
    int? concurrency,
  }) {
    return LLMSettings(
      apiUrl: apiUrl ?? this.apiUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      prompt: prompt ?? this.prompt,
      concurrency: concurrency ?? this.concurrency,
    );
  }
}

class LLMSettingsNotifier extends StateNotifier<LLMSettings> {
  static const String _prefix = 'llm_settings_';

  LLMSettingsNotifier() : super(const LLMSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = LLMSettings(
        apiUrl: prefs.getString('${_prefix}api_url') ?? state.apiUrl,
        apiKey: prefs.getString('${_prefix}api_key') ?? state.apiKey,
        model: prefs.getString('${_prefix}model') ?? state.model,
        prompt: prefs.getString('${_prefix}prompt') ?? state.prompt,
        concurrency: prefs.getInt('${_prefix}concurrency') ?? state.concurrency,
      );
    } catch (e) {
      // ignore
    }
  }

  Future<void> updateSettings(LLMSettings settings) async {
    state = settings;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${_prefix}api_url', settings.apiUrl);
      await prefs.setString('${_prefix}api_key', settings.apiKey);
      await prefs.setString('${_prefix}model', settings.model);
      await prefs.setString('${_prefix}prompt', settings.prompt);
      await prefs.setInt('${_prefix}concurrency', settings.concurrency);
    } catch (e) {
      // ignore
    }
  }
}

final llmSettingsProvider =
    StateNotifierProvider<LLMSettingsNotifier, LLMSettings>((ref) {
  return LLMSettingsNotifier();
});

/// 翻译源设置
class TranslationSourceNotifier extends StateNotifier<TranslationSource> {
  static const String _preferenceKey = 'translation_source';

  TranslationSourceNotifier() : super(TranslationSource.google) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedValue = prefs.getString(_preferenceKey);

      if (savedValue != null) {
        final source = TranslationSource.values.firstWhere(
          (s) => s.value == savedValue,
          orElse: () => TranslationSource.google,
        );
        state = source;
      }
    } catch (e) {
      state = TranslationSource.google;
    }
  }

  Future<void> updateSource(TranslationSource source) async {
    state = source;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_preferenceKey, state.value);
    } catch (e) {
      // ignore
    }
  }
}

final translationSourceProvider =
    StateNotifierProvider<TranslationSourceNotifier, TranslationSource>((ref) {
  return TranslationSourceNotifier();
});

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
  final bool blurCoverInApp;
  final bool maskTitle;
  final String customTitle;

  const PrivacyModeSettings({
    this.enabled = false,
    this.blurCover = true,
    this.blurCoverInApp = false,
    this.maskTitle = false,
    this.customTitle = '正在播放音频',
  });

  PrivacyModeSettings copyWith({
    bool? enabled,
    bool? blurCover,
    bool? blurCoverInApp,
    bool? maskTitle,
    String? customTitle,
  }) {
    return PrivacyModeSettings(
      enabled: enabled ?? this.enabled,
      blurCover: blurCover ?? this.blurCover,
      blurCoverInApp: blurCoverInApp ?? this.blurCoverInApp,
      maskTitle: maskTitle ?? this.maskTitle,
      customTitle: customTitle ?? this.customTitle,
    );
  }
}

/// 防社死设置控制器
class PrivacyModeSettingsNotifier extends StateNotifier<PrivacyModeSettings> {
  static const String _enabledKey = 'privacy_mode_enabled';
  static const String _blurCoverKey = 'privacy_mode_blur_cover';
  static const String _blurCoverInAppKey = 'privacy_mode_blur_cover_in_app';
  static const String _maskTitleKey = 'privacy_mode_mask_title';
  static const String _customTitleKey = 'privacy_mode_custom_title';

  PrivacyModeSettingsNotifier() : super(const PrivacyModeSettings()) {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final blurCover = prefs.getBool(_blurCoverKey) ?? true;
      final blurCoverInApp =
          prefs.getBool(_blurCoverInAppKey) ?? false;

      state = PrivacyModeSettings(
        enabled: prefs.getBool(_enabledKey) ?? false,
        blurCover: blurCover,
        blurCoverInApp: blurCoverInApp,
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

  Future<void> setBlurCoverInApp(bool blur) async {
    state = state.copyWith(blurCoverInApp: blur);
    await _savePreference(_blurCoverInAppKey, blur);
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

/// 分页大小设置
class PageSizeNotifier extends StateNotifier<int> {
  static const String _preferenceKey = 'page_size_preference';
  static const int defaultSize = 40;

  PageSizeNotifier() : super(defaultSize) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedValue = prefs.getInt(_preferenceKey);
      if (savedValue != null && [20, 40, 60, 100].contains(savedValue)) {
        state = savedValue;
      }
    } catch (e) {
      state = defaultSize;
    }
  }

  Future<void> updatePageSize(int size) async {
    if (![20, 40, 60, 100].contains(size)) return;
    state = size;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_preferenceKey, size);
    } catch (e) {
      // ignore
    }
  }
}

/// 分页大小提供者
final pageSizeProvider = StateNotifierProvider<PageSizeNotifier, int>((ref) {
  return PageSizeNotifier();
});

/// 默认排序设置状态
class DefaultSortState {
  final SortOrder order;
  final SortDirection direction;

  const DefaultSortState({
    this.order = SortOrder.release,
    this.direction = SortDirection.desc,
  });
}

/// 默认排序设置
class DefaultSortNotifier extends StateNotifier<DefaultSortState> {
  static const String _orderKey = 'default_sort_order';
  static const String _directionKey = 'default_sort_direction';

  DefaultSortNotifier() : super(const DefaultSortState()) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final orderValue = prefs.getString(_orderKey);
      final directionValue = prefs.getString(_directionKey);

      SortOrder order = SortOrder.release;
      if (orderValue != null) {
        order = SortOrder.values.firstWhere(
          (e) => e.value == orderValue,
          orElse: () => SortOrder.release,
        );
      }

      SortDirection direction = SortDirection.desc;
      if (directionValue != null) {
        direction = SortDirection.values.firstWhere(
          (e) => e.value == directionValue,
          orElse: () => SortDirection.desc,
        );
      }

      state = DefaultSortState(order: order, direction: direction);
    } catch (e) {
      // ignore
    }
  }

  Future<void> updateDefaultSort(
      SortOrder order, SortDirection direction) async {
    state = DefaultSortState(order: order, direction: direction);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_orderKey, order.value);
      await prefs.setString(_directionKey, direction.value);
    } catch (e) {
      // ignore
    }
  }
}

/// 默认排序提供者
final defaultSortProvider =
    StateNotifierProvider<DefaultSortNotifier, DefaultSortState>((ref) {
  return DefaultSortNotifier();
});
