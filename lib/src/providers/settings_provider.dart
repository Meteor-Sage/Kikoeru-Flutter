import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Triggers when Settings screen should refresh cache-related information.
final settingsCacheRefreshTriggerProvider = StateProvider<int>((ref) => 0);

/// Triggers when Subtitle Library screen should refresh (e.g., after path change).
final subtitleLibraryRefreshTriggerProvider = StateProvider<int>((ref) => 0);

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
