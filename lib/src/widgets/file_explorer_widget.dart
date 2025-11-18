import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';

import '../models/work.dart';
import '../models/audio_track.dart';
import '../models/download_task.dart';
import '../providers/auth_provider.dart';
import '../providers/audio_provider.dart';
import '../providers/lyric_provider.dart';
import '../providers/settings_provider.dart';
import '../services/download_service.dart';
import '../services/cache_service.dart';
import '../services/translation_service.dart';
import '../utils/file_icon_utils.dart';
import '../utils/snackbar_util.dart';
import 'responsive_dialog.dart';
import 'image_gallery_screen.dart';
import 'text_preview_screen.dart';
import 'pdf_preview_screen.dart';

class FileExplorerWidget extends ConsumerStatefulWidget {
  final Work work;

  const FileExplorerWidget({
    super.key,
    required this.work,
  });

  @override
  ConsumerState<FileExplorerWidget> createState() => _FileExplorerWidgetState();
}

class _FileExplorerWidgetState extends ConsumerState<FileExplorerWidget> {
  List<dynamic> _rootFiles = [];
  final Set<String> _expandedFolders = {}; // 记录展开的文件夹路径
  final Map<String, bool> _downloadedFiles = {}; // hash -> downloaded
  final Map<String, String> _fileRelativePaths = {}; // hash -> relative path
  bool _isLoading = false;
  String? _errorMessage;
  String? _mainFolderPath; // 主文件夹路径
  ScaffoldMessengerState? _scaffoldMessenger;
  StreamSubscription<List<DownloadTask>>? _downloadTasksSubscription;

  // 翻译相关状态
  bool _isTranslating = false;
  bool _showTranslation = false;
  String _translationProgress = '';
  final Map<String, String> _translationCache = {}; // 原文 -> 译文

  @override
  void initState() {
    super.initState();
    _loadWorkTree();
    // 监听下载任务变化
    _listenToDownloadTasks();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  void dispose() {
    _downloadTasksSubscription?.cancel();
    _scaffoldMessenger = null;
    super.dispose();
  }

  // 监听下载任务变化，当有任务完成或被删除时重新检测
  void _listenToDownloadTasks() {
    final downloadService = DownloadService.instance;
    _downloadTasksSubscription = downloadService.tasksStream.listen((tasks) {
      // 过滤出与当前作品相关的任务
      final workTasks = tasks.where((t) => t.workId == widget.work.id).toList();

      // 如果有任务状态变化，重新检测已下载文件
      if (workTasks.isNotEmpty) {
        _checkDownloadedFiles();
      }
    });
  }

  Future<void> _loadWorkTree() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiService = ref.read(kikoeruApiServiceProvider);
      final files = await apiService.getWorkTracks(widget.work.id);

      // 注意：不要在这里更新全局文件列表
      // 只在播放音频时才更新，避免浏览其他作品时影响当前播放的歌曲?

      setState(() {
        _rootFiles = files;
        _isLoading = false;
        // 识别主文件夹并自动展开
        _identifyAndExpandMainFolder();
      });

      // 检查已下载的文件
      _checkDownloadedFiles();
    } catch (e) {
      setState(() {
        _errorMessage = '加载文件失败: $e';
        _isLoading = false;
      });
    }
  }

  // 检查已下载的文件
  Future<void> _checkDownloadedFiles() async {
    final downloadService = DownloadService.instance;
    _downloadedFiles.clear();
    _fileRelativePaths.clear();

    void collectHashes(List<dynamic> items, String parentPath) {
      for (final item in items) {
        final type = item['type'] ?? '';
        // 收集所有文件类型的hash（除了文件夹）
        if (type != 'folder' && item['hash'] != null) {
          _downloadedFiles[item['hash']] = false;
          final title = item['title'] ?? item['name'] ?? 'unknown';
          final relativePath =
              parentPath.isEmpty ? title : '$parentPath/$title';
          _fileRelativePaths[item['hash']] = relativePath;
        }
        final children = item['children'] as List<dynamic>?;
        if (children != null && type == 'folder') {
          final folderName = item['title'] ?? item['name'] ?? '';
          final nextPath =
              parentPath.isEmpty ? folderName : '$parentPath/$folderName';
          collectHashes(children, nextPath);
        } else if (children != null) {
          collectHashes(children, parentPath);
        }
      }
    }

    collectHashes(_rootFiles, '');

    for (final hash in _downloadedFiles.keys) {
      final filePath =
          await downloadService.getDownloadedFilePath(widget.work.id, hash);
      if (filePath != null) {
        _downloadedFiles[hash] = true;
        continue;
      }

      final relativePath = _fileRelativePaths[hash];
      if (relativePath != null) {
        final downloadDir = await downloadService.getDownloadDirectory();
        final localFile =
            File('${downloadDir.path}/${widget.work.id}/$relativePath');
        if (await localFile.exists()) {
          _downloadedFiles[hash] = true;
        }
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  // 识别主文件夹：音频数量最多的目录，如果有多个则选择文本文件最多的
  void _identifyAndExpandMainFolder() {
    if (_rootFiles.isEmpty) return;

    // 如果根目录本身包含音频文件，则不需要展开
    final rootHasAudio = _rootFiles.any((item) => item['type'] == 'audio');
    if (rootHasAudio) {
      _mainFolderPath = '';
      return;
    }

    // 收集所有文件夹及其统计信息（使用LinkedHashMap保持顺序）
    final Map<String, Map<String, dynamic>> folderStats = {};

    void analyzeFolders(List<dynamic> items, String parentPath) {
      for (final item in items) {
        if (item['type'] == 'folder') {
          final children = item['children'] as List<dynamic>?;
          if (children != null && children.isNotEmpty) {
            final itemPath = _getItemPath(parentPath, item);

            // 统计该文件夹的音频和文本文件数量
            final stats = _countFilesInFolder(children);
            folderStats[itemPath] = {
              'audioCount': stats['audioCount'],
              'textCount': stats['textCount'],
              'item': item,
            };

            // 递归分析子文件夹
            analyzeFolders(children, itemPath);
          }
        }
      }
    }

    analyzeFolders(_rootFiles, '');

    if (folderStats.isEmpty) {
      _mainFolderPath = null;
      return;
    }

    // 找出音频数量最多的文件夹
    int maxAudioCount = 0;
    for (final stats in folderStats.values) {
      if (stats['audioCount'] > maxAudioCount) {
        maxAudioCount = stats['audioCount'];
      }
    }

    // 在音频数量最多的文件夹中，先选择文本文件最多的
    String? mainFolder;
    int maxTextCount = -1;
    List<String> candidateFolders = [];

    for (final entry in folderStats.entries) {
      if (entry.value['audioCount'] == maxAudioCount) {
        final textCount = entry.value['textCount'] as int;
        if (textCount > maxTextCount) {
          maxTextCount = textCount;
          candidateFolders = [entry.key];
        } else if (textCount == maxTextCount) {
          candidateFolders.add(entry.key);
        }
      }
    }

    // 如果有多个文件夹的音频和文本数量都相同，按照音频格式偏好选择
    if (candidateFolders.length > 1) {
      final formatPreference = ref.read(audioFormatPreferenceProvider);
      mainFolder = _selectByAudioFormatPreference(
          candidateFolders, formatPreference.priority);
    } else if (candidateFolders.isNotEmpty) {
      mainFolder = candidateFolders.first;
    }

    if (mainFolder != null) {
      _mainFolderPath = mainFolder;
      // 展开主文件夹路径上的所有父文件夹
      _expandPathToFolder(mainFolder);
      print(
          '[FileExplorer] 识别到主文件夹 $_mainFolderPath (音频:$maxAudioCount, 文本:$maxTextCount)');
    }
  }

  // 统计文件夹中的音频和文本文件数量（仅统计当前层级，不递归子文件夹）
  Map<String, int> _countFilesInFolder(List<dynamic> items) {
    int audioCount = 0;
    int textCount = 0;

    for (final child in items) {
      if (child['type'] == 'audio') {
        audioCount++;
      } else if (FileIconUtils.isTextFile(child)) {
        textCount++;
      }
      // 不再递归统计子文件夹中的文件
    }

    return {'audioCount': audioCount, 'textCount': textCount};
  }

  // 根据音频格式偏好选择文件夹
  // 返回包含最高优先级音频格式的文件夹
  String _selectByAudioFormatPreference(
      List<String> folderPaths, List<AudioFormat> priorityOrder) {
    // 为每个候选文件夹找到其包含的最高优先级格式
    Map<String, int> folderPriorities = {};

    for (final folderPath in folderPaths) {
      // 找到该文件夹下的所有音频文件
      final folderChildren = _findFolderChildren(folderPath);
      int highestPriority = priorityOrder.length; // 初始化为最低优先级（越大越低优先级）

      for (final child in folderChildren) {
        if (child['type'] == 'audio') {
          final fileName =
              (child['title'] ?? child['name'] ?? '').toLowerCase();
          // 检查文件扩展名
          for (int i = 0; i < priorityOrder.length; i++) {
            final format = priorityOrder[i];
            if (fileName.endsWith('.${format.extension}')) {
              if (i < highestPriority) {
                highestPriority = i;
              }
              break; // 找到格式后跳出循环
            }
          }
        }
      }

      folderPriorities[folderPath] = highestPriority;
    }

    // 选择优先级最高（数值最小）的文件夹
    String selectedFolder = folderPaths.first;
    int bestPriority = folderPriorities[selectedFolder]!;

    for (final folderPath in folderPaths) {
      final priority = folderPriorities[folderPath]!;
      if (priority < bestPriority) {
        bestPriority = priority;
        selectedFolder = folderPath;
      }
    }

    return selectedFolder;
  }

  // 查找指定路径的文件夹中的子项
  List<dynamic> _findFolderChildren(String targetPath) {
    final segments = targetPath.split('/');
    List<dynamic> currentItems = _rootFiles;

    for (final segment in segments) {
      bool found = false;
      for (final item in currentItems) {
        final title = item['title'] ?? item['name'] ?? '';
        if (title == segment && item['type'] == 'folder') {
          currentItems = item['children'] ?? [];
          found = true;
          break;
        }
      }
      if (!found) {
        return []; // 路径不存在
      }
    }

    return currentItems;
  }

  // 展开到指定文件夹的路径
  void _expandPathToFolder(String targetPath) {
    // 将路径拆分，展开所有父级文件夹
    final segments = targetPath.split('/');
    String currentPath = '';

    for (int i = 0; i < segments.length; i++) {
      if (i == 0) {
        currentPath = segments[i];
      } else {
        currentPath = '$currentPath/${segments[i]}';
      }

      if (!_expandedFolders.contains(currentPath)) {
        _expandedFolders.add(currentPath);
      }
    }
  }

  // 切换文件夹展开/折叠状态
  void _toggleFolder(String path) {
    setState(() {
      if (_expandedFolders.contains(path)) {
        _expandedFolders.remove(path);
      } else {
        _expandedFolders.add(path);
      }
    });
  }

  // 生成文件/文件夹的唯一路径
  String _getItemPath(String parentPath, dynamic item) {
    final title = item['title'] ?? item['name'] ?? 'unknown';
    return parentPath.isEmpty ? title : '$parentPath/$title';
  }

  // 格式化持续时间（秒 -> 时:分:秒 或 分:秒）
  String _formatDuration(dynamic durationValue) {
    if (durationValue == null) return '';

    // duration 可能是整数（秒）或浮点数（秒）
    final totalSeconds = durationValue is int
        ? durationValue
        : (durationValue is double ? durationValue.toInt() : 0);

    if (totalSeconds <= 0) return '';

    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
  }

  void _showSnackBar(SnackBar snackBar) {
    if (!mounted) return;
    
    // 提取 SnackBar 的内容和类型
    final content = snackBar.content;
    String message = '';
    
    if (content is Text) {
      message = content.data ?? '';
    } else if (content is Row) {
      // 处理包含 Row 的 SnackBar
      final children = content.children;
      for (final child in children) {
        if (child is Text) {
          message = child.data ?? '';
          break;
        } else if (child is Expanded) {
          final expandedChild = child.child;
          if (expandedChild is Text) {
            message = expandedChild.data ?? '';
            break;
          }
        }
      }
    }
    
    if (message.isEmpty) {
      // 如果无法提取消息，使用原始方法
      final messenger = _scaffoldMessenger ?? ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(snackBar);
      return;
    }
    
    // 根据背景色判断类型
    final backgroundColor = snackBar.backgroundColor;
    final duration = snackBar.duration ?? const Duration(seconds: 2);
    
    if (backgroundColor == Colors.red) {
      SnackBarUtil.showError(context, message, duration: duration);
    } else if (backgroundColor == Colors.green) {
      SnackBarUtil.showSuccess(context, message, duration: duration);
    } else if (backgroundColor == Colors.orange) {
      SnackBarUtil.showWarning(context, message, duration: duration);
    } else {
      // 默认使用 info
      SnackBarUtil.showInfo(context, message, duration: duration);
    }
  }

  void _playAudioFile(dynamic audioFile, String parentPath) async {
    final authState = ref.read(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';
    // Current work cover URL (used as track artwork)
    String? coverUrl;
    if (host.isNotEmpty) {
      String normalizedUrl = host;
      if (!host.startsWith('http://') && !host.startsWith('https://')) {
        normalizedUrl = 'https://$host';
      }
      coverUrl = token.isNotEmpty
          ? '$normalizedUrl/api/cover/${widget.work.id}?token=$token'
          : '$normalizedUrl/api/cover/${widget.work.id}';
    }

    // 获取音频文件信息
    final hash = audioFile['hash'];
    final title = audioFile['title'] ?? audioFile['name'] ?? '未知';

    // 获取当前作品的完整文件树（用于歌词查找）
    try {
      final apiService = ref.read(kikoeruApiServiceProvider);
      final allFiles = await apiService.getWorkTracks(widget.work.id);

      // 只在播放音频时更新全局文件列表，这样歌词才能正确关联
      ref.read(fileListControllerProvider.notifier).updateFiles(allFiles);
    } catch (e) {
      print('获取完整文件树失败 $e');
      // 即使获取失败也继续播放，只是可能没有歌词
    }

    // 获取同一目录下的所有音频文件（不递归子文件夹）
    final audioFiles = _getAudioFilesFromSameDirectory(parentPath);
    final currentIndex = audioFiles.indexWhere((file) => file['hash'] == hash);

    if (currentIndex == -1) {
      _showSnackBar(
        SnackBar(
          content: Text('无法找到音频文件: $title'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    // 构建播放队列
    final downloadService = DownloadService.instance;
    final List<AudioTrack> audioTracks = [];

    for (final file in audioFiles) {
      final fileHash = file['hash'];
      final fileTitle = file['title'] ?? file['name'] ?? '未知';

      // 优先级: 本地下载文件 → 缓存文件 → 网络URL
      String audioUrl = '';
      if (fileHash != null) {
        // 1. 检查是否有本地下载的文件
        final localPath = await downloadService.getDownloadedFilePath(
          widget.work.id,
          fileHash,
        );

        if (localPath != null) {
          // 使用本地文件（file:// 协议）
          audioUrl = 'file://$localPath';
          print('[FileExplorer] 使用本地下载的音频: $fileHash');
        } else if (_downloadedFiles[fileHash] == true) {
          // 检查是否是手动复制的本地文件
          final relativePath = _fileRelativePaths[fileHash];
          if (relativePath != null) {
            final downloadDir = await downloadService.getDownloadDirectory();
            final localFile =
                File('${downloadDir.path}/${widget.work.id}/$relativePath');
            if (await localFile.exists()) {
              audioUrl = 'file://${localFile.path}';
              print('[FileExplorer] 使用手动复制的音频: $fileHash');
            }
          }
        }

        // 2. 如果没有本地文件，检查缓存
        if (audioUrl.isEmpty) {
          final cachedPath = await CacheService.getCachedAudioFile(fileHash);
          if (cachedPath != null) {
            audioUrl = 'file://$cachedPath';
            print('[FileExplorer] 使用缓存的音频: $fileHash');
          }
        }
      }

      // 3. 如果缓存也没有，使用网络URL
      if (audioUrl.isEmpty) {
        if (file['mediaStreamUrl'] != null &&
            file['mediaStreamUrl'].toString().isNotEmpty) {
          audioUrl = file['mediaStreamUrl'];
        } else if (host.isNotEmpty && fileHash != null) {
          String normalizedUrl = host;
          if (!host.startsWith('http://') && !host.startsWith('https://')) {
            normalizedUrl = 'https://$host';
          }
          audioUrl = '$normalizedUrl/api/media/stream/$fileHash?token=$token';
        }
      }

      if (audioUrl.isNotEmpty) {
        // 获取声优信息
        final vaNames = widget.work.vas?.map((va) => va.name).toList() ?? [];
        final artistInfo = vaNames.isNotEmpty ? vaNames.join(', ') : null;

        audioTracks.add(AudioTrack(
          id: fileHash ?? fileTitle,
          url: audioUrl,
          title: fileTitle,
          artist: artistInfo,
          album: widget.work.title,
          artworkUrl: coverUrl,
          duration: file['duration'] != null
              ? Duration(milliseconds: (file['duration'] * 1000).round())
              : null,
          workId: widget.work.id,
          hash: fileHash,
        ));
      }
    }

    if (audioTracks.isEmpty) {
      _showSnackBar(
        const SnackBar(
          content: Text('没有找到可播放的音频文件'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    print('播放音频: $title');
    print('播放队列包含 ${audioTracks.length} 个文件');

    // 播放音频队列，从当前选择的文件开始
    final adjustedIndex =
        audioTracks.indexWhere((track) => track.id == (hash ?? title));
    final startIndex = adjustedIndex != -1 ? adjustedIndex : 0;

    ref.read(audioPlayerControllerProvider.notifier).playTracks(
          audioTracks,
          startIndex: startIndex,
        );

    // 注意：歌词会通过 lyricAutoLoaderProvider 自动加载
    // 不需要手动调用 loadLyricForTrack

    // 显示提示
    _showSnackBar(
      SnackBar(
        content: Text('正在播放: $title (${startIndex + 1}/${audioTracks.length})'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // 获取同一目录下的所有音频文件（不递归子文件夹）
  List<dynamic> _getAudioFilesFromSameDirectory(String targetPath) {
    final List<dynamic> audioFiles = [];

    // 如果是根目录
    if (targetPath.isEmpty) {
      for (final item in _rootFiles) {
        if (item['type'] == 'audio') {
          audioFiles.add(item);
        }
      }
      return audioFiles;
    }

    // 查找目标路径对应的文件夹
    List<dynamic>? findFolderByPath(List<dynamic> items, String currentPath) {
      for (final item in items) {
        if (item['type'] == 'folder') {
          final itemPath = _getItemPath(currentPath, item);

          if (itemPath == targetPath) {
            // 找到目标文件夹，返回其子文件夹
            return item['children'] as List<dynamic>?;
          }

          // 继续在子文件夹中查找
          if (item['children'] != null) {
            final result = findFolderByPath(item['children'], itemPath);
            if (result != null) return result;
          }
        }
      }
      return null;
    }

    final folderContents = findFolderByPath(_rootFiles, '');
    if (folderContents != null) {
      for (final item in folderContents) {
        if (item['type'] == 'audio') {
          audioFiles.add(item);
        }
      }
    }

    return audioFiles;
  }

  // 手动加载字幕
  Future<void> _loadLyricManually(dynamic file) async {
    final title = file['title'] ?? file['name'] ?? '未知文件';

    // 检查当前是否有播放中的音频
    final currentTrackAsync = ref.read(currentTrackProvider);
    final currentTrack = currentTrackAsync.value;

    if (currentTrack == null) {
      if (mounted) {
        _showSnackBar(
          const SnackBar(
            content: Text('当前没有播放的音频，无法加载字幕'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // 二次确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ResponsiveAlertDialog(
        title: const Text('加载字幕'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('确定要将以下文件加载为当前音频的字幕吗？'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '字幕文件：',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '当前音频：',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      currentTrack.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '注意：切换到其他音频时，字幕将自动恢复为默认匹配方式。',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定加载'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // 显示加载中提示
    _showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 12),
            Text('正在加载字幕...'),
          ],
        ),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      // 调用手动加载字幕方法，传入当前作品ID
      await ref.read(lyricControllerProvider.notifier).loadLyricManually(
            file,
            workId: widget.work.id,
          );

      if (mounted) {
        _showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('字幕加载成功：$title'),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('字幕加载失败：$e'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _previewImageFile(dynamic file) async {
    final authState = ref.read(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';

    if (host.isEmpty) {
      _showSnackBar(
        const SnackBar(
          content: Text('无法预览图片：缺少必要信息'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    String normalizedUrl = host;
    if (!host.startsWith('http://') && !host.startsWith('https://')) {
      normalizedUrl = 'https://$host';
    }

    // 获取当前目录下所有图片文件（递归遍历整个树）
    final imageFiles = _getImageFilesFromCurrentDirectory();
    final currentIndex =
        imageFiles.indexWhere((f) => f['hash'] == file['hash']);

    if (currentIndex == -1) {
      _showSnackBar(
        const SnackBar(
          content: Text('无法找到图片文件'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 构建图片URL列表，优先使用本地文件，否则使用网络URL
    final imageItems = <Map<String, String>>[];

    for (final f in imageFiles) {
      final hash = f['hash'] ?? '';
      final title = f['title'] ?? f['name'] ?? '未知图片';
      String imageUrl;

      // 1. 先检查是否已下载到本地
      final relativePath = _fileRelativePaths[hash];
      if (relativePath != null && _downloadedFiles[hash] == true) {
        try {
          final downloadService = DownloadService.instance;
          final downloadDir = await downloadService.getDownloadDirectory();
          final localPath =
              '${downloadDir.path}/${widget.work.id}/$relativePath';
          final localFile = File(localPath);

          if (await localFile.exists()) {
            imageUrl = 'file://$localPath';
          } else {
            // 本地文件不存在，使用网络URL
            imageUrl = '$normalizedUrl/api/media/stream/$hash?token=$token';
          }
        } catch (e) {
          print('[FileExplorer] 检查本地图片文件失败: $e');
          imageUrl = '$normalizedUrl/api/media/stream/$hash?token=$token';
        }
      } else {
        // 2. 本地文件不存在，使用网络URL (CachedImageWidget会检查缓存)
        imageUrl = '$normalizedUrl/api/media/stream/$hash?token=$token';
      }

      imageItems.add({
        'url': imageUrl,
        'title': title,
        'hash': hash,
      });
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ImageGalleryScreen(
          images: imageItems,
          initialIndex: currentIndex,
          workId: widget.work.id, // 传递作品ID用于缓存
        ),
      ),
    );
  }

  // 获取当前目录下所有图片文件（递归遍历整个树）
  List<dynamic> _getImageFilesFromCurrentDirectory() {
    final List<dynamic> imageFiles = [];

    void extractImageFiles(List<dynamic> items) {
      for (final item in items) {
        if (FileIconUtils.isImageFile(item)) {
          imageFiles.add(item);
        } else if (item['type'] == 'folder' && item['children'] != null) {
          extractImageFiles(item['children']);
        }
      }
    }

    if (_rootFiles.isNotEmpty) {
      extractImageFiles(_rootFiles);
    }

    return imageFiles;
  }

  Future<void> _previewTextFile(dynamic file) async {
    final authState = ref.read(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';
    final hash = file['hash'];
    final title = file['title'] ?? file['name'] ?? '未知文本';

    if (hash == null || host.isEmpty) {
      _showSnackBar(
        const SnackBar(
          content: Text('无法预览文本：缺少必要信息'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    String textUrl;

    // 1. 先检查是否已下载到本地
    final relativePath = _fileRelativePaths[hash];
    if (relativePath != null && _downloadedFiles[hash] == true) {
      try {
        final downloadService = DownloadService.instance;
        final downloadDir = await downloadService.getDownloadDirectory();
        final localPath = '${downloadDir.path}/${widget.work.id}/$relativePath';
        final localFile = File(localPath);

        if (await localFile.exists()) {
          textUrl = 'file://$localPath';
        } else {
          // 本地文件不存在，使用网络URL
          String normalizedUrl = host;
          if (!host.startsWith('http://') && !host.startsWith('https://')) {
            normalizedUrl = 'https://$host';
          }
          textUrl = '$normalizedUrl/api/media/stream/$hash?token=$token';
        }
      } catch (e) {
        print('[FileExplorer] 检查本地文本文件失败: $e');
        String normalizedUrl = host;
        if (!host.startsWith('http://') && !host.startsWith('https://')) {
          normalizedUrl = 'https://$host';
        }
        textUrl = '$normalizedUrl/api/media/stream/$hash?token=$token';
      }
    } else {
      // 2. 本地文件不存在，使用网络URL (TextPreviewScreen会检查缓存)
      String normalizedUrl = host;
      if (!host.startsWith('http://') && !host.startsWith('https://')) {
        normalizedUrl = 'https://$host';
      }
      textUrl = '$normalizedUrl/api/media/stream/$hash?token=$token';
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TextPreviewScreen(
          textUrl: textUrl,
          title: title,
          workId: widget.work.id, // 传递作品ID
          hash: hash, // 传递文件hash
        ),
      ),
    );
  }

  Future<void> _previewPdfFile(dynamic file) async {
    final authState = ref.read(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';
    final hash = file['hash'];
    final title = file['title'] ?? file['name'] ?? '未知PDF';

    if (hash == null || host.isEmpty) {
      _showSnackBar(
        const SnackBar(
          content: Text('无法预览PDF：缺少必要信息'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 1. 先检查是否已下载到本地
    final relativePath = _fileRelativePaths[hash];
    if (relativePath != null && _downloadedFiles[hash] == true) {
      try {
        final downloadService = DownloadService.instance;
        final downloadDir = await downloadService.getDownloadDirectory();
        final localPath = '${downloadDir.path}/${widget.work.id}/$relativePath';
        final localFile = File(localPath);

        if (await localFile.exists()) {
          // 使用本地文件
          if (!mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PdfPreviewScreen(
                pdfUrl: 'file://$localPath',
                title: title,
                workId: widget.work.id,
                hash: hash,
              ),
            ),
          );
          return;
        }
      } catch (e) {
        print('[FileExplorer] 检查本地PDF文件失败: $e');
      }
    }

    // 2. 本地文件不存在,构造网络URL(PdfPreviewScreen会检查缓存)
    String normalizedUrl = host;
    if (!host.startsWith('http://') && !host.startsWith('https://')) {
      normalizedUrl = 'https://$host';
    }
    final pdfUrl = '$normalizedUrl/api/media/stream/$hash?token=$token';

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PdfPreviewScreen(
          pdfUrl: pdfUrl,
          title: title,
          workId: widget.work.id,
          hash: hash,
        ),
      ),
    );
  }

  // 使用系统播放器播放视频文件
  Future<void> _playVideoWithSystemPlayer(dynamic videoFile) async {
    final authState = ref.read(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';
    final hash = videoFile['hash'] ?? '';

    if (hash.isEmpty) {
      if (mounted) {
        _showSnackBar(
          const SnackBar(
            content: Text('无法播放视频：缺少文件标识'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    Uri uri;
    String uriString; // 用于错误信息显示

    // 1. 先检查是否已下载到本地
    final relativePath = _fileRelativePaths[hash];
    if (relativePath != null && _downloadedFiles[hash] == true) {
      try {
        final downloadService = DownloadService.instance;
        final downloadDir = await downloadService.getDownloadDirectory();
        final localPath = '${downloadDir.path}/${widget.work.id}/$relativePath';
        final localFile = File(localPath);

        if (await localFile.exists()) {
          // 使用本地文件 - 通过 open_filex 打开
          uriString = localPath;
          print('[FileExplorer] 使用本地视频文件: $localPath');

          try {
            final result = await OpenFilex.open(localPath);
            if (result.type != ResultType.done) {
              if (mounted) {
                _showSnackBar(
                  SnackBar(
                    content: Text('无法打开视频文件: ${result.message}'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            }
          } catch (e) {
            if (mounted) {
              _showSnackBar(
                SnackBar(
                  content: Text('打开视频文件时出错: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
          return;
        } else {
          // 本地文件不存在，使用网络URL
          if (host.isEmpty || token.isEmpty) {
            if (mounted) {
              _showSnackBar(
                const SnackBar(
                  content: Text('无法播放视频：缺少必要参数'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }
          String normalizedUrl = host;
          if (!host.startsWith('http://') && !host.startsWith('https://')) {
            normalizedUrl = 'https://$host';
          }
          final videoUrl = '$normalizedUrl/api/media/stream/$hash?token=$token';
          uri = Uri.parse(videoUrl);
          uriString = videoUrl;
        }
      } catch (e) {
        print('[FileExplorer] 检查本地视频文件失败: $e');
        if (host.isEmpty || token.isEmpty) {
          if (mounted) {
            _showSnackBar(
              const SnackBar(
                content: Text('无法播放视频：缺少必要参数'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        String normalizedUrl = host;
        if (!host.startsWith('http://') && !host.startsWith('https://')) {
          normalizedUrl = 'https://$host';
        }
        final videoUrl = '$normalizedUrl/api/media/stream/$hash?token=$token';
        uri = Uri.parse(videoUrl);
        uriString = videoUrl;
      }
    } else {
      // 2. 本地文件不存在，使用网络URL
      if (host.isEmpty || token.isEmpty) {
        if (mounted) {
          _showSnackBar(
            const SnackBar(
              content: Text('无法播放视频：缺少必要参数'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      String normalizedUrl = host;
      if (!host.startsWith('http://') && !host.startsWith('https://')) {
        normalizedUrl = 'https://$host';
      }
      final videoUrl = '$normalizedUrl/api/media/stream/$hash?token=$token';
      uri = Uri.parse(videoUrl);
      uriString = videoUrl;
    }

    // 使用 url_launcher 打开网络视频URL
    try {
      final canLaunch = await canLaunchUrl(uri);

      if (canLaunch) {
        // 先尝试外部应用模式
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!launched && mounted) {
          // 如果外部应用模式失败，尝试浏览器模式
          await launchUrl(
            uri,
            mode: LaunchMode.externalNonBrowserApplication,
          );
        }
      } else {
        // 如果无法通过 url_launcher 打开，显示提示

        if (mounted) {
          // 提供复制链接的选项
          showDialog(
            context: context,
            builder: (context) => ResponsiveAlertDialog(
              title: const Text('无法直接播放'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('系统无法找到支持的视频播放器。'),
                    const SizedBox(height: 12),
                    const Text('您可以：'),
                    const Text('1. 复制链接到外部播放器（如MX Player、VLC）'),
                    const Text('2. 在浏览器中打开'),
                    const SizedBox(height: 12),
                    SelectableText(
                      uriString,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    // 在浏览器中打开
                    await launchUrl(uri, mode: LaunchMode.platformDefault);
                  },
                  child: const Text('在浏览器中打开'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          SnackBar(
            content: Text('播放视频时出错: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 直接返回文件列表，占满全部空间
    return _buildFileList();
  }

  Widget _buildFileList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadWorkTree,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_rootFiles.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              '没有文件',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // 使用Column构建树形结构，可以自由展开
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 翻译按钮栏
          Container(
            padding: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _showTranslation
                        ? '资源文件 (已翻译 ${_translationCache.length} 项)'
                        : '资源文件',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isTranslating ? null : _translateAllNames,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _showTranslation
                              ? Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.3)
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _isTranslating
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                )
                              : Icon(
                                  Icons.g_translate,
                                  size: 16,
                                  color: _showTranslation
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withOpacity(0.7),
                                ),
                          if (!_isTranslating) ...[
                            const SizedBox(width: 4),
                            Text(
                              _showTranslation ? '原' : '译',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _showTranslation
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(0.7),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 翻译进度显示
          if (_isTranslating)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _translationProgress,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          // 文件树列表
          ..._buildFileTree(_rootFiles, ''),
        ],
      ),
    );
  }

  // 递归构建文件树
  List<Widget> _buildFileTree(List<dynamic> items, String parentPath,
      {int level = 0}) {
    final List<Widget> widgets = [];

    for (final item in items) {
      final type = item['type'] ?? '';
      final originalTitle = item['title'] ?? item['name'] ?? '未知文件';
      final title = _getDisplayName(originalTitle); // 使用翻译后的名称
      final isFolder = type == 'folder';
      final children = item['children'] as List<dynamic>?;
      final itemPath = _getItemPath(parentPath, item);
      final isExpanded = _expandedFolders.contains(itemPath);

      // 文件/文件夹项
      widgets.add(
        InkWell(
          onTap: () {
            if (isFolder) {
              // 文件夹点击展开/折叠
              _toggleFolder(itemPath);
            } else {
              // 文件点击处理
              _handleFileTap(item, title, parentPath);
            }
          },
          child: Padding(
            padding: EdgeInsets.only(
              left: 8.0 + (level * 20.0), // 减少基础左边距，使用8px
              right: 8.0, // 减少右边距为8px
              top: 8.0,
              bottom: 8.0,
            ),
            child: Row(
              children: [
                // 展开/折叠图标（仅文件夹）
                if (isFolder)
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 20,
                  )
                else
                  const SizedBox(width: 20),
                const SizedBox(width: 8),
                // 文件图标（带已下载徽章）
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Stack(
                    children: [
                      Icon(
                        FileIconUtils.getFileIconFromMap(item),
                        color: FileIconUtils.getFileIconColorFromMap(item),
                        size: 24,
                      ),
                      // 已下载徽章
                      if (type != 'folder' &&
                          item['hash'] != null &&
                          (_downloadedFiles[item['hash']] ?? false))
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check_circle,
                              color: Colors.green[600],
                              size: 13,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // 文件名（已下载文件带遮罩）+ 持续时间
                Expanded(
                  child: Opacity(
                    opacity: type != 'folder' &&
                            item['hash'] != null &&
                            (_downloadedFiles[item['hash']] ?? false)
                        ? 0.5
                        : 1.0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        // 显示持续时间（仅音频和视频）
                        if ((type == 'audio' ||
                                FileIconUtils.isVideoFile(item)) &&
                            item['duration'] != null)
                          Text(
                            _formatDuration(item['duration']),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // 操作按钮
                if (type == 'audio')
                  IconButton(
                    onPressed: () {
                      if (FileIconUtils.isVideoFile(item)) {
                        _playVideoWithSystemPlayer(item);
                      } else {
                        _playAudioFile(item, parentPath);
                      }
                    },
                    icon: Icon(FileIconUtils.isVideoFile(item)
                        ? Icons.video_library
                        : Icons.play_arrow),
                    color: FileIconUtils.isVideoFile(item)
                        ? Colors.blue
                        : Colors.green,
                    iconSize: 20,
                  )
                else if (FileIconUtils.isImageFile(item) ||
                    FileIconUtils.isTextFile(item) ||
                    FileIconUtils.isPdfFile(item))
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (FileIconUtils.isTextFile(item) &&
                          FileIconUtils.isLyricFile(
                              item['title'] ?? item['name'] ?? ''))
                        IconButton(
                          onPressed: () => _loadLyricManually(item),
                          icon: const Icon(Icons.subtitles),
                          color: Colors.orange,
                          tooltip: '加载为字幕',
                          iconSize: 20,
                        ),
                      IconButton(
                        onPressed: () {
                          if (FileIconUtils.isImageFile(item)) {
                            _previewImageFile(item);
                          } else if (FileIconUtils.isPdfFile(item)) {
                            _previewPdfFile(item);
                          } else {
                            _previewTextFile(item);
                          }
                        },
                        icon: const Icon(Icons.visibility),
                        color: Colors.blue,
                        tooltip: '预览',
                        iconSize: 20,
                      ),
                    ],
                  )
                else if (isFolder && children != null)
                  Text(
                    '${children.length} 项',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

      // 如果是展开的文件夹，递归显示子项
      if (isFolder && isExpanded && children != null && children.isNotEmpty) {
        widgets.addAll(_buildFileTree(children, itemPath, level: level + 1));
      }
    }

    return widgets;
  }

  // 收集所有文件和文件夹的名称
  List<String> _collectAllNames(List<dynamic> items) {
    final List<String> names = [];

    void collect(List<dynamic> items) {
      for (final item in items) {
        final title = item['title'] ?? item['name'] ?? '';
        if (title.isNotEmpty && !names.contains(title)) {
          names.add(title);
        }

        // 递归处理子文件夹
        if (item['type'] == 'folder' && item['children'] != null) {
          collect(item['children'] as List<dynamic>);
        }
      }
    }

    collect(items);
    return names;
  }

  // 分块批量翻译所有文件/文件夹名称
  Future<void> _translateAllNames() async {
    if (_isTranslating) return;

    // 如果已有翻译，直接切换显示
    if (_translationCache.isNotEmpty) {
      setState(() {
        _showTranslation = !_showTranslation;
      });
      return;
    }

    setState(() {
      _isTranslating = true;
      _translationProgress = '准备翻译...';
    });

    try {
      // 1. 收集所有需要翻译的名称
      final allNames = _collectAllNames(_rootFiles);

      if (allNames.isEmpty) {
        setState(() {
          _isTranslating = false;
        });
        _showSnackBar(
          const SnackBar(
            content: Text('没有需要翻译的内容'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      // 2. 分块翻译（每块最多500字符，避免URL长度限制）
      const maxChunkSize = 500;
      final List<String> chunks = [];
      String currentChunk = '';

      for (final name in allNames) {
        final separator = currentChunk.isEmpty ? '' : '\n';
        final estimatedLength =
            currentChunk.length + separator.length + name.length;

        if (estimatedLength > maxChunkSize && currentChunk.isNotEmpty) {
          chunks.add(currentChunk);
          currentChunk = name;
        } else {
          currentChunk += separator + name;
        }
      }

      if (currentChunk.isNotEmpty) {
        chunks.add(currentChunk);
      }

      // 3. 逐块翻译
      final translationService = TranslationService();
      final List<String> translatedChunks = [];

      for (int i = 0; i < chunks.length; i++) {
        setState(() {
          _translationProgress = '翻译中 ${i + 1}/${chunks.length}';
        });

        try {
          final translated = await translationService.translate(
            chunks[i],
            sourceLang: 'ja',
          );
          translatedChunks.add(translated);
        } catch (e) {
          print('[FileExplorer] 翻译块 $i 失败: $e');
          // 翻译失败时保留原文
          translatedChunks.add(chunks[i]);
        }

        // 添加小延迟避免频繁请求
        if (i < chunks.length - 1) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      // 4. 构建翻译缓存（原文 -> 译文映射）
      final allTranslatedNames = translatedChunks.join('\n').split('\n');

      for (int i = 0;
          i < allNames.length && i < allTranslatedNames.length;
          i++) {
        _translationCache[allNames[i]] = allTranslatedNames[i];
      }

      setState(() {
        _showTranslation = true;
        _isTranslating = false;
        _translationProgress = '';
      });

      _showSnackBar(
        SnackBar(
          content: Text('翻译完成：${_translationCache.length} 个项目'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      setState(() {
        _isTranslating = false;
        _translationProgress = '';
      });

      _showSnackBar(
        SnackBar(
          content: Text('翻译失败: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // 获取显示的名称（根据翻译状态）
  String _getDisplayName(String originalName) {
    if (_showTranslation && _translationCache.containsKey(originalName)) {
      return _translationCache[originalName]!;
    }
    return originalName;
  }

  // 处理文件点击
  void _handleFileTap(dynamic file, String title, String parentPath) {
    if (FileIconUtils.isVideoFile(file)) {
      _playVideoWithSystemPlayer(file);
    } else if (file['type'] == 'audio') {
      _playAudioFile(file, parentPath);
    } else if (FileIconUtils.isImageFile(file)) {
      _previewImageFile(file);
    } else if (FileIconUtils.isPdfFile(file)) {
      _previewPdfFile(file);
    } else if (FileIconUtils.isTextFile(file)) {
      _previewTextFile(file);
    } else {
      _showSnackBar(
        SnackBar(
          content: Text('暂不支持打开此类型文件: $title'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
