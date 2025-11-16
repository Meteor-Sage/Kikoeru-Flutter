import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../models/lyric.dart';
import '../models/audio_track.dart';
import '../services/cache_service.dart';
import 'auth_provider.dart';
import 'audio_provider.dart';

// 歌词状态
class LyricState {
  final List<LyricLine> lyrics;
  final bool isLoading;
  final String? error;
  final String? lyricUrl;

  LyricState({
    this.lyrics = const [],
    this.isLoading = false,
    this.error,
    this.lyricUrl,
  });

  LyricState copyWith({
    List<LyricLine>? lyrics,
    bool? isLoading,
    String? error,
    String? lyricUrl,
  }) {
    return LyricState(
      lyrics: lyrics ?? this.lyrics,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      lyricUrl: lyricUrl ?? this.lyricUrl,
    );
  }
}

// 歌词控制器
class LyricController extends StateNotifier<LyricState> {
  final Ref ref;

  LyricController(this.ref) : super(LyricState());

  // 根据音频轨道查找并加载歌词
  Future<void> loadLyricForTrack(
      AudioTrack track, List<dynamic> allFiles) async {
    print(
        '[Lyric] 尝试加载: track="${track.title}", workId=${track.workId}, 文件数=${allFiles.length}');
    state = state.copyWith(isLoading: true, error: null);

    try {
      // 查找歌词文件
      final lyricFile = _findLyricFile(track, allFiles);

      if (lyricFile == null) {
        print('[Lyric] 未找到匹配歌词: track="${track.title}"');
        state = LyricState(lyrics: [], isLoading: false);
        return;
      }

      print(
          '[Lyric] 找到匹配歌词: title="${lyricFile['title']}", type="${lyricFile['type']}", hash=${lyricFile['hash']}');

      // 获取认证信息
      final authState = ref.read(authProvider);
      final host = authState.host ?? '';
      final token = authState.token ?? '';
      final hash = lyricFile['hash'];
      final workId = track.workId;

      if (hash == null || host.isEmpty || workId == null) {
        state = LyricState(lyrics: [], isLoading: false);
        return;
      }

      // 构建歌词 URL
      String normalizedUrl = host;
      if (!host.startsWith('http://') && !host.startsWith('https://')) {
        normalizedUrl = 'https://$host';
      }
      final lyricUrl = '$normalizedUrl/api/media/stream/$hash?token=$token';

      String? content;

      // 1. 先尝试从缓存加载（包括下载文件和缓存文件）
      final cachedContent = await CacheService.getCachedTextContent(
        workId: workId,
        hash: hash,
      );

      if (cachedContent != null) {
        print('[Lyric] 从缓存加载歌词: $hash');
        content = cachedContent;
      } else {
        // 2. 缓存未命中，从网络下载
        print('[Lyric] 从网络下载歌词: $hash');
        final dio = Dio();
        final response = await dio.get(
          lyricUrl,
          options: Options(
            responseType: ResponseType.plain,
            receiveTimeout: const Duration(seconds: 30),
          ),
        );

        if (response.statusCode == 200) {
          content = response.data as String;

          // 3. 缓存歌词内容
          await CacheService.cacheTextContent(
            workId: workId,
            hash: hash,
            content: content,
          );
        } else {
          state = LyricState(
            lyrics: [],
            isLoading: false,
            error: 'HTTP ${response.statusCode}',
          );
          return;
        }
      }

      // 4. 解析歌词
      final lyrics = LyricParser.parse(content); // 自动检测格式
      state = LyricState(
        lyrics: lyrics,
        isLoading: false,
        lyricUrl: lyricUrl,
      );
    } catch (e) {
      state = LyricState(
        lyrics: [],
        isLoading: false,
        error: '加载歌词失败: $e',
      );
    }
  }

  // 查找歌词文件
  dynamic _findLyricFile(AudioTrack track, List<dynamic> allFiles) {
    // 获取音频文件名（去掉可能的扩展名）
    final trackTitle = track.title;
    final audioNameWithoutExt = _removeAudioExtension(trackTitle);

    // 文本文件扩展名列表
    final textExtensions = ['.vtt', '.srt', '.txt', '.lrc'];

    // 递归搜索歌词文件
    dynamic searchInFiles(List<dynamic> files) {
      for (final file in files) {
        final fileType = file['type'] ?? '';
        final fileName = (file['title'] ?? file['name'] ?? '').toLowerCase();

        // 如果是文件夹，递归搜索
        if (fileType == 'folder' && file['children'] != null) {
          final result = searchInFiles(file['children']);
          if (result != null) return result;
          continue;
        }

        // 检查是否是文本文件
        final isTextFile = fileType == 'text' ||
            textExtensions.any((ext) => fileName.endsWith(ext));

        if (!isTextFile) continue;

        // 检查文件名是否匹配
        // 规则1: 完全匹配（音频文件名 + 文本扩展名）
        for (final ext in textExtensions) {
          if (fileName == '${trackTitle.toLowerCase()}$ext') {
            print('[Lyric] 规则1匹配: track="${track.title}", lyric="$fileName"');
            return file;
          }
        }

        // 规则2: 去掉音频扩展名后匹配（音频文件名去后缀 + 文本扩展名）
        for (final ext in textExtensions) {
          if (fileName == '${audioNameWithoutExt.toLowerCase()}$ext') {
            print('[Lyric] 规则2匹配: track="${track.title}", lyric="$fileName"');
            return file;
          }
        }
      }
      return null;
    }

    return searchInFiles(allFiles);
  }

  // 移除音频文件扩展名
  String _removeAudioExtension(String fileName) {
    final audioExtensions = [
      '.mp3',
      '.wav',
      '.flac',
      '.m4a',
      '.aac',
      '.ogg',
      '.opus',
      '.wma',
      '.mp4',
    ];

    final lowerName = fileName.toLowerCase();
    for (final ext in audioExtensions) {
      if (lowerName.endsWith(ext)) {
        return fileName.substring(0, fileName.length - ext.length);
      }
    }
    return fileName;
  }

  // 清空歌词
  void clearLyrics() {
    state = LyricState();
  }

  // 手动加载字幕文件
  Future<void> loadLyricManually(dynamic lyricFile) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // 获取认证信息
      final authState = ref.read(authProvider);
      final host = authState.host ?? '';
      final token = authState.token ?? '';
      final hash = lyricFile['hash'];

      if (hash == null || host.isEmpty) {
        state = LyricState(
          lyrics: [],
          isLoading: false,
          error: '缺少必要信息',
        );
        return;
      }

      // 构建歌词 URL
      String normalizedUrl = host;
      if (!host.startsWith('http://') && !host.startsWith('https://')) {
        normalizedUrl = 'https://$host';
      }
      final lyricUrl = '$normalizedUrl/api/media/stream/$hash?token=$token';

      String content;

      // 1. 先尝试从缓存加载（包括下载文件和缓存文件）
      final workId = lyricFile['workId'] as int?;
      final cachedContent = workId != null
          ? await CacheService.getCachedTextContent(
              workId: workId,
              hash: hash,
            )
          : null;

      if (cachedContent != null) {
        print('[Lyric] 手动加载 - 从缓存加载歌词: $hash');
        content = cachedContent;
      } else {
        // 2. 缓存未命中，从网络下载
        print('[Lyric] 手动加载 - 从网络下载歌词: $hash');
        final dio = Dio();
        final response = await dio.get(
          lyricUrl,
          options: Options(
            responseType: ResponseType.plain,
            receiveTimeout: const Duration(seconds: 30),
          ),
        );

        if (response.statusCode == 200) {
          content = response.data as String;

          // 3. 缓存歌词内容
          if (workId != null) {
            await CacheService.cacheTextContent(
              workId: workId,
              hash: hash,
              content: content,
            );
          }
        } else {
          state = LyricState(
            lyrics: [],
            isLoading: false,
            error: 'HTTP ${response.statusCode}',
          );
          return;
        }
      }

      // 4. 解析歌词
      final lyrics = LyricParser.parse(content);
      state = LyricState(
        lyrics: lyrics,
        isLoading: false,
        lyricUrl: lyricUrl,
      );
    } catch (e) {
      state = LyricState(
        lyrics: [],
        isLoading: false,
        error: '加载字幕失败: $e',
      );
      rethrow;
    }
  }
}

// 存储当前工作的文件列表（用于查找歌词）
class FileListState {
  final List<dynamic> files;

  FileListState({this.files = const []});
}

class FileListController extends StateNotifier<FileListState> {
  FileListController() : super(FileListState());

  void updateFiles(List<dynamic> files) {
    state = FileListState(files: files);
  }

  void clear() {
    state = FileListState();
  }
}

final fileListControllerProvider =
    StateNotifierProvider<FileListController, FileListState>((ref) {
  return FileListController();
});

// Provider
final lyricControllerProvider =
    StateNotifierProvider<LyricController, LyricState>((ref) {
  return LyricController(ref);
});

// 监听曲目变化，自动重新加载歌词
final lyricAutoLoaderProvider = Provider<void>((ref) {
  final currentTrack = ref.watch(currentTrackProvider);
  final fileListState = ref.watch(fileListControllerProvider);

  currentTrack.whenData((track) {
    if (track != null && fileListState.files.isNotEmpty) {
      // 延迟加载，避免同步问题
      Future.microtask(() {
        ref.read(lyricControllerProvider.notifier).loadLyricForTrack(
              track,
              fileListState.files,
            );
      });
    } else if (track == null) {
      // 没有播放时清空歌词
      ref.read(lyricControllerProvider.notifier).clearLyrics();
    }
  });
});

// 当前歌词文本 Provider（根据播放位置）
final currentLyricTextProvider = Provider<String?>((ref) {
  final lyricState = ref.watch(lyricControllerProvider);
  final position = ref.watch(positionProvider);

  if (lyricState.lyrics.isEmpty) return null;

  return position.when(
    data: (pos) => LyricParser.getCurrentLyric(lyricState.lyrics, pos),
    loading: () => null,
    error: (_, __) => null,
  );
});
