import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../models/lyric.dart';
import '../models/audio_track.dart';
import '../services/cache_service.dart';
import '../services/subtitle_library_service.dart';
import 'auth_provider.dart';
import 'audio_provider.dart';
import 'settings_provider.dart';

// 歌词状态
class LyricState {
  final List<LyricLine> lyrics;
  final bool isLoading;
  final String? error;
  final String? lyricUrl;
  final Duration timelineOffset; // 时间轴偏移（毫秒）

  LyricState({
    this.lyrics = const [],
    this.isLoading = false,
    this.error,
    this.lyricUrl,
    this.timelineOffset = Duration.zero,
  });

  LyricState copyWith({
    List<LyricLine>? lyrics,
    bool? isLoading,
    String? error,
    String? lyricUrl,
    Duration? timelineOffset,
  }) {
    return LyricState(
      lyrics: lyrics ?? this.lyrics,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      lyricUrl: lyricUrl ?? this.lyricUrl,
      timelineOffset: timelineOffset ?? this.timelineOffset,
    );
  }

  /// 获取应用了时间轴偏移后的歌词列表
  List<LyricLine> get adjustedLyrics {
    if (timelineOffset == Duration.zero) {
      return lyrics;
    }
    return lyrics.map((lyric) => lyric.applyOffset(timelineOffset)).toList();
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
      // 获取字幕库优先级设置
      final libraryPriority = ref.read(subtitleLibraryPriorityProvider);
      final isLibraryFirst = libraryPriority == SubtitleLibraryPriority.highest;

      print('[Lyric] 字幕库优先级: ${libraryPriority.displayName}');

      // 根据设置决定查找顺序
      if (isLibraryFirst) {
        // 优先级1：从字幕库查找匹配的字幕文件
        final libraryLyricPath = await _findLyricInLibrary(track);
        if (libraryLyricPath != null) {
          print('[Lyric] 从字幕库加载: $libraryLyricPath');
          await loadLyricFromLocalFile(libraryLyricPath);
          return;
        }
      }

      // 从完整文件树查找歌词文件
      final lyricFile = _findLyricFile(track, allFiles);

      if (lyricFile == null) {
        // 如果文件树未找到且优先级为最后，尝试字幕库
        if (!isLibraryFirst) {
          print('[Lyric] 文件树未找到，尝试字幕库');
          final libraryLyricPath = await _findLyricInLibrary(track);
          if (libraryLyricPath != null) {
            print('[Lyric] 从字幕库加载: $libraryLyricPath');
            await loadLyricFromLocalFile(libraryLyricPath);
            return;
          }
        }

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
      final fileName = lyricFile['title'] ?? lyricFile['name'];
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
        fileName: fileName,
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

  // 从字幕库查找匹配的字幕文件
  Future<String?> _findLyricInLibrary(AudioTrack track) async {
    try {
      final libraryDir =
          await SubtitleLibraryService.getSubtitleLibraryDirectory();
      if (!await libraryDir.exists()) {
        return null;
      }

      final trackTitle = track.title;
      final audioNameWithoutExt = _removeAudioExtension(trackTitle);
      final textExtensions = ['.vtt', '.srt', '.txt', '.lrc'];
      final workId = track.workId;

      print('[Lyric] 在字幕库中查找: track="$trackTitle", workId=$workId');

      // 优先级1: 查找作品ID文件夹
      if (workId != null) {
        // 尝试查找 RJ{workId} 文件夹
        final rjFolderPath = '${libraryDir.path}/RJ$workId';
        final rjFolder = Directory(rjFolderPath);
        if (await rjFolder.exists()) {
          final match = await _searchLyricInFolder(
            rjFolder,
            trackTitle,
            audioNameWithoutExt,
            textExtensions,
          );
          if (match != null) {
            print('[Lyric] 在RJ$workId文件夹找到匹配: $match');
            return match;
          }
        }

        // 尝试查找纯数字ID文件夹
        final idFolderPath = '${libraryDir.path}/$workId';
        final idFolder = Directory(idFolderPath);
        if (await idFolder.exists()) {
          final match = await _searchLyricInFolder(
            idFolder,
            trackTitle,
            audioNameWithoutExt,
            textExtensions,
          );
          if (match != null) {
            print('[Lyric] 在$workId文件夹找到匹配: $match');
            return match;
          }
        }

        // 递归查找包含作品ID的文件夹
        final match = await _recursiveFindByWorkId(
          libraryDir,
          workId.toString(),
          trackTitle,
          audioNameWithoutExt,
          textExtensions,
        );
        if (match != null) {
          print('[Lyric] 在作品ID相关文件夹找到匹配: $match');
          return match;
        }
      }

      // 优先级2: 查找"已保存"文件夹
      final savedFolderPath = '${libraryDir.path}/已保存';
      final savedFolder = Directory(savedFolderPath);
      if (await savedFolder.exists()) {
        final match = await _searchLyricInFolder(
          savedFolder,
          trackTitle,
          audioNameWithoutExt,
          textExtensions,
        );
        if (match != null) {
          print('[Lyric] 在"已保存"文件夹找到匹配: $match');
          return match;
        }
      }

      print('[Lyric] 字幕库中未找到匹配的字幕');
      return null;
    } catch (e) {
      print('[Lyric] 字幕库查找出错: $e');
      return null;
    }
  }

  // 递归查找包含作品ID的文件夹
  Future<String?> _recursiveFindByWorkId(
    Directory dir,
    String workId,
    String trackTitle,
    String audioNameWithoutExt,
    List<String> textExtensions,
  ) async {
    try {
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          final folderName = entity.path.split(Platform.pathSeparator).last;
          // 检查文件夹名是否包含作品ID或RJ+作品ID
          if (folderName == workId || folderName == 'RJ$workId') {
            final match = await _searchLyricInFolder(
              entity,
              trackTitle,
              audioNameWithoutExt,
              textExtensions,
            );
            if (match != null) return match;
          }
          // 继续递归搜索子文件夹
          final match = await _recursiveFindByWorkId(
            entity,
            workId,
            trackTitle,
            audioNameWithoutExt,
            textExtensions,
          );
          if (match != null) return match;
        }
      }
    } catch (e) {
      // 忽略权限错误等
    }
    return null;
  }

  // 在指定文件夹中递归搜索匹配的字幕文件
  Future<String?> _searchLyricInFolder(
    Directory folder,
    String trackTitle,
    String audioNameWithoutExt,
    List<String> textExtensions,
  ) async {
    try {
      await for (final entity in folder.list(recursive: true)) {
        if (entity is File) {
          final fileName =
              entity.path.split(Platform.pathSeparator).last.toLowerCase();

          // 检查是否是字幕文件
          final isLyricFile =
              textExtensions.any((ext) => fileName.endsWith(ext));
          if (!isLyricFile) continue;

          // 规则1: 完全匹配（音频文件名 + 字幕扩展名）
          for (final ext in textExtensions) {
            if (fileName == '${trackTitle.toLowerCase()}$ext') {
              return entity.path;
            }
          }

          // 规则2: 去掉音频扩展名后匹配
          for (final ext in textExtensions) {
            if (fileName == '${audioNameWithoutExt.toLowerCase()}$ext') {
              return entity.path;
            }
          }
        }
      }
    } catch (e) {
      // 忽略权限错误等
    }
    return null;
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

  /// 调整字幕轴偏移
  void adjustTimelineOffset(Duration offset) {
    state = state.copyWith(timelineOffset: offset);
  }

  /// 重置字幕轴偏移
  void resetTimelineOffset() {
    state = state.copyWith(timelineOffset: Duration.zero);
  }

  /// 获取导出格式的字幕内容（应用了时间轴偏移）
  String exportLyrics({String format = 'lrc'}) {
    final adjustedLyrics = state.adjustedLyrics;
    if (adjustedLyrics.isEmpty) return '';

    final buffer = StringBuffer();

    if (format == 'lrc') {
      // LRC 格式
      for (final lyric in adjustedLyrics) {
        if (lyric.text.isEmpty) continue; // 跳过占位符
        final minutes = lyric.startTime.inMinutes;
        final seconds = lyric.startTime.inSeconds % 60;
        final centiseconds = (lyric.startTime.inMilliseconds % 1000) ~/ 10;
        buffer.writeln(
            '[${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${centiseconds.toString().padLeft(2, '0')}]${lyric.text}');
      }
    } else if (format == 'vtt') {
      // WebVTT 格式
      buffer.writeln('WEBVTT\n');
      for (final lyric in adjustedLyrics) {
        if (lyric.text.isEmpty) continue; // 跳过占位符
        buffer.writeln(_formatWebVTTTime(lyric.startTime) +
            ' --> ' +
            _formatWebVTTTime(lyric.endTime));
        buffer.writeln(lyric.text);
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  String _formatWebVTTTime(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    final milliseconds = duration.inMilliseconds % 1000;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${milliseconds.toString().padLeft(3, '0')}';
  }

  // 手动加载字幕文件
  /// 从本地文件路径加载字幕（用于字幕库）
  Future<void> loadLyricFromLocalFile(String filePath) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      print('[Lyric] 从本地文件加载字幕: $filePath');

      // 读取文件内容
      final file = File(filePath);
      if (!await file.exists()) {
        state = LyricState(
          lyrics: [],
          isLoading: false,
          error: '文件不存在',
        );
        return;
      }

      final content = await file.readAsString();

      // 解析歌词
      final lyrics = LyricParser.parse(content);
      state = LyricState(
        lyrics: lyrics,
        isLoading: false,
        lyricUrl: 'file://$filePath',
      );

      print('[Lyric] 成功从本地文件加载字幕，共 ${lyrics.length} 行');
    } catch (e) {
      print('[Lyric] 从本地文件加载字幕失败: $e');
      state = LyricState(
        lyrics: [],
        isLoading: false,
        error: '加载字幕失败: $e',
      );
      rethrow;
    }
  }

  Future<void> loadLyricManually(dynamic lyricFile, {int? workId}) async {
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
      // 优先级：传入的 workId > lyricFile 中的 workId > 当前播放音轨的 workId
      int? effectiveWorkId = workId ?? lyricFile['workId'] as int?;
      if (effectiveWorkId == null) {
        final currentTrackAsync = ref.read(currentTrackProvider);
        final currentTrack = currentTrackAsync.value;
        effectiveWorkId = currentTrack?.workId;
      }

      final fileName = lyricFile['title'] ?? lyricFile['name'];
      final cachedContent = effectiveWorkId != null
          ? await CacheService.getCachedTextContent(
              workId: effectiveWorkId,
              hash: hash,
              fileName: fileName,
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
          if (effectiveWorkId != null) {
            await CacheService.cacheTextContent(
              workId: effectiveWorkId,
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

  // 使用调整后的歌词
  final adjustedLyrics = lyricState.adjustedLyrics;

  return position.when(
    data: (pos) => LyricParser.getCurrentLyric(adjustedLyrics, pos),
    loading: () => null,
    error: (_, __) => null,
  );
});
