import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../models/work.dart';
import '../services/download_path_service.dart';
import '../services/download_service.dart';
import '../services/translation_service.dart';
import '../services/subtitle_library_service.dart';
import '../models/audio_track.dart';
import '../providers/audio_provider.dart';
import '../providers/lyric_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/file_icon_utils.dart';
import '../utils/snackbar_util.dart';
import 'responsive_dialog.dart';
import 'image_gallery_screen.dart';
import 'text_preview_screen.dart';
import 'pdf_preview_screen.dart';

/// 离线文件浏览器 - 显示已下载的文件
/// 只显示硬盘上实际存在的文件，不显示未下载的文件
class OfflineFileExplorerWidget extends ConsumerStatefulWidget {
  final Work work;
  final List<dynamic>? fileTree; // 从 work_metadata.json 中读取的文件树

  const OfflineFileExplorerWidget({
    super.key,
    required this.work,
    this.fileTree,
  });

  @override
  ConsumerState<OfflineFileExplorerWidget> createState() =>
      _OfflineFileExplorerWidgetState();
}

class _OfflineFileExplorerWidgetState
    extends ConsumerState<OfflineFileExplorerWidget> {
  List<dynamic> _localFiles = []; // 仅包含本地存在的文件
  final Set<String> _expandedFolders = {}; // 记录展开的文件夹路径
  final Map<String, bool> _fileExists = {}; // hash -> exists on disk
  final Set<String> _audioWithLibrarySubtitles = {}; // 存储在字幕库中有匹配字幕的音频文件名
  bool _isLoading = true;
  String? _errorMessage;
  String? _mainFolderPath; // 主文件夹路径
  late final FileListController _fileListController;

  // 翻译相关状态
  bool _showTranslation = false;
  final Map<String, String> _translationCache = {}; // 原文 -> 译文
  final Set<String> _translatingItems = {}; // 正在翻译的项目

  @override
  void initState() {
    super.initState();
    _fileListController = ref.read(fileListControllerProvider.notifier);
    _loadLocalFiles();
  }

  @override
  void dispose() {
    // 离线页面关闭时清空文件列表，避免影响其他作品
    // 使用 Future.microtask 延迟执行，避免在 dispose 中直接修改 provider
    Future.microtask(() => _fileListController.clear());
    super.dispose();
  }

  // 加载本地存在的文件
  Future<void> _loadLocalFiles() async {
    if (widget.fileTree == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = '没有文件树信息';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final downloadDir = await DownloadPathService.getDownloadDirectory();
      final workDir = Directory('${downloadDir.path}/${widget.work.id}');

      if (!await workDir.exists()) {
        setState(() {
          _isLoading = false;
          _errorMessage = '作品文件夹不存在';
        });
        return;
      }

      // 递归检查并过滤本地存在的文件
      _localFiles = await _filterLocalFiles(widget.fileTree!, workDir.path, '');
      // 更新全局文件列表供歌词自动加载使用
      _fileListController.updateFiles(List<dynamic>.from(_localFiles));

      // 检查字幕库中的匹配项
      await _checkLibrarySubtitles();

      // 识别主文件夹并自动展开（需要在检查字幕库后执行）
      _identifyAndExpandMainFolder();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '加载文件失败: $e';
      });
    }
  }

  // 递归过滤本地存在的文件
  Future<List<dynamic>> _filterLocalFiles(
      List<dynamic> items, String workDirPath, String parentPath) async {
    final List<dynamic> filteredItems = [];

    for (final item in items) {
      final type = _getProperty(item, 'type', defaultValue: '');
      final title = _getProperty(item, 'title', defaultValue: 'unknown');
      final hash = _getProperty(item, 'hash');

      if (type == 'folder') {
        final children = _getProperty(item, 'children') as List<dynamic>?;

        if (children != null && children.isNotEmpty) {
          final folderPath = parentPath.isEmpty ? title : '$parentPath/$title';
          final filteredChildren =
              await _filterLocalFiles(children, workDirPath, folderPath);

          // 只添加包含文件的文件夹
          if (filteredChildren.isNotEmpty) {
            // 创建文件夹的 Map 副本
            if (item is Map<String, dynamic>) {
              final folderCopy = Map<String, dynamic>.from(item);
              folderCopy['children'] = filteredChildren;
              filteredItems.add(folderCopy);
            } else {
              // 如果是 AudioFile 对象，转换为 Map
              final folderMap = <String, dynamic>{
                'type': 'folder',
                'title': title,
                'children': filteredChildren,
              };
              filteredItems.add(folderMap);
            }
          }
        }
      } else if (hash != null) {
        // 检查文件是否存在
        final relativePath = parentPath.isEmpty ? title : '$parentPath/$title';
        final file = File('$workDirPath/$relativePath');

        if (await file.exists()) {
          _fileExists[hash] = true;

          // 根据文件扩展名确定正确的类型
          String fileType = type; // 默认使用现有类型

          // 如果类型是 'file' 或为空，根据扩展名重新判断
          if (type == 'file' || type == null || type.isEmpty) {
            fileType = FileIconUtils.inferFileType(title);
          }

          // 统一创建或修正 Map
          if (item is Map<String, dynamic>) {
            // 如果是 Map，可能需要修正类型
            if (item['type'] != fileType) {
              final correctedMap = Map<String, dynamic>.from(item);
              correctedMap['type'] = fileType;
              filteredItems.add(correctedMap);
            } else {
              filteredItems.add(item);
            }
          } else {
            // 如果是 AudioFile 对象，转换为 Map
            final fileMap = <String, dynamic>{
              'type': fileType,
              'title': title,
              'hash': hash,
              'duration': _getProperty(item, 'duration'),
              'size': _getProperty(item, 'size'),
            };
            filteredItems.add(fileMap);
          }
        }
      }
    }

    return filteredItems;
  }

  // 安全获取对象属性（支持 Map 和 AudioFile 对象）
  dynamic _getProperty(dynamic item, String key, {dynamic defaultValue}) {
    if (item == null) return defaultValue;

    if (item is Map) {
      return item[key] ?? defaultValue;
    } else {
      // AudioFile 对象
      try {
        switch (key) {
          case 'type':
            return (item as dynamic).type ?? defaultValue;
          case 'title':
            return (item as dynamic).title ?? defaultValue;
          case 'name':
            return (item as dynamic).title ?? defaultValue;
          case 'hash':
            return (item as dynamic).hash ?? defaultValue;
          case 'children':
            return (item as dynamic).children ?? defaultValue;
          case 'size':
            return (item as dynamic).size ?? defaultValue;
          case 'mediaType':
            return (item as dynamic).type ?? defaultValue;
          case 'duration':
            return (item as dynamic).duration ?? defaultValue;
          default:
            return defaultValue;
        }
      } catch (e) {
        return defaultValue;
      }
    }
  }

  // 检查字幕库中哪些音频文件有匹配的字幕
  Future<void> _checkLibrarySubtitles() async {
    try {
      final libraryDir =
          await SubtitleLibraryService.getSubtitleLibraryDirectory();
      if (!await libraryDir.exists()) {
        return;
      }

      _audioWithLibrarySubtitles.clear();
      final workId = widget.work.id;
      final parsedFolderPath = '${libraryDir.path}/已解析';

      // 生成可能的文件夹名称列表（支持带前导零的格式）
      final possibleFolderNames = [
        'RJ$workId',
        'RJ0$workId',
        'BJ$workId',
        'BJ0$workId',
        'VJ$workId',
        'VJ0$workId',
      ];

      // 收集所有音频文件名
      final audioFiles = <String>[];
      void collectAudioFiles(List<dynamic> items) {
        for (final item in items) {
          final type = _getProperty(item, 'type', defaultValue: '');
          final title = _getProperty(item, 'title', defaultValue: '');

          // 检查是否是音频文件（通过类型或文件名后缀）
          // 修复：wav等格式可能没有被正确标记为audio类型
          if (type == 'audio' ||
              FileIconUtils.inferFileType(title) == 'audio') {
            if (title.isNotEmpty) {
              audioFiles.add(title);
            }
          }
          final children = _getProperty(item, 'children') as List<dynamic>?;
          if (children != null) {
            collectAudioFiles(children);
          }
        }
      }

      collectAudioFiles(_localFiles);

      // 检查每个可能的文件夹
      for (final folderName in possibleFolderNames) {
        final folderPath = '$parsedFolderPath/$folderName';
        final folder = Directory(folderPath);
        if (!await folder.exists()) continue;

        // 遍历字幕库文件夹，查找匹配的字幕
        await for (final entity in folder.list(recursive: true)) {
          if (entity is File) {
            final fileName = entity.path.split(Platform.pathSeparator).last;

            // 检查是否有音频文件匹配这个字幕
            for (final audioFile in audioFiles) {
              if (SubtitleLibraryService.isSubtitleForAudio(
                  fileName, audioFile)) {
                _audioWithLibrarySubtitles.add(audioFile);
                break;
              }
            }
          }
        }
      }

      print(
          '[OfflineFileExplorer] 字幕库匹配: ${_audioWithLibrarySubtitles.length} 个音频文件有字幕');
    } catch (e) {
      print('[OfflineFileExplorer] 检查字幕库失败: $e');
    }
  }

  // 识别主文件夹：音频数量最多的目录，如果有多个则选择文本文件最多的
  void _identifyAndExpandMainFolder() {
    if (_localFiles.isEmpty) return;

    // 如果根目录本身包含音频文件，则不需要展开
    final rootHasAudio = _localFiles
        .any((item) => _getProperty(item, 'type', defaultValue: '') == 'audio');
    if (rootHasAudio) {
      _mainFolderPath = '';
      return;
    }

    // 收集所有文件夹及其统计信息
    final Map<String, Map<String, dynamic>> folderStats = {};

    void analyzeFolders(List<dynamic> items, String parentPath) {
      for (final item in items) {
        if (_getProperty(item, 'type', defaultValue: '') == 'folder') {
          final children = _getProperty(item, 'children') as List<dynamic>?;
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

    analyzeFolders(_localFiles, '');

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
          '[OfflineFileExplorer] 识别到主文件夹 $_mainFolderPath (音频:$maxAudioCount, 文本:$maxTextCount)');
    }
  }

  // 统计文件夹中的音频和文本文件数量（仅统计当前层级，不递归子文件夹）
  Map<String, int> _countFilesInFolder(List<dynamic> items) {
    int audioCount = 0;
    int textCount = 0;

    for (final child in items) {
      if (_getProperty(child, 'type', defaultValue: '') == 'audio') {
        audioCount++;

        // 检查该音频是否在字幕库中有匹配的字幕
        final audioTitle = _getProperty(child, 'title', defaultValue: '');
        if (_audioWithLibrarySubtitles.contains(audioTitle)) {
          textCount++; // 字幕库匹配也算作文本文件
        }
      } else if (FileIconUtils.isTextFile(child)) {
        textCount++;
      }
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
        if (_getProperty(child, 'type', defaultValue: '') == 'audio') {
          final fileName =
              _getProperty(child, 'title', defaultValue: '').toLowerCase();
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
    List<dynamic> currentItems = _localFiles;

    for (final segment in segments) {
      bool found = false;
      for (final item in currentItems) {
        final title = _getProperty(item, 'title', defaultValue: '');
        if (title == segment &&
            _getProperty(item, 'type', defaultValue: '') == 'folder') {
          currentItems = _getProperty(item, 'children') as List<dynamic>? ?? [];
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

  // 生成文件/文件夹的唯一路径
  String _getItemPath(String parentPath, dynamic item) {
    final title = _getProperty(item, 'title', defaultValue: 'unknown');
    return parentPath.isEmpty ? title : '$parentPath/$title';
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

  // 格式化文件大小
  String _formatFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';

    const units = ['B', 'KB', 'MB', 'GB'];
    int unitIndex = 0;
    double size = bytes.toDouble();

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    if (unitIndex == 0) {
      return '$bytes B';
    } else {
      return '${size.toStringAsFixed(2)} ${units[unitIndex]}';
    }
  }

  // 获取文件大小（从元数据或本地文件）
  Future<int?> _getFileSize(dynamic item, String parentPath) async {
    // 先尝试从元数据获取
    final metaSize = _getProperty(item, 'size');
    if (metaSize != null && metaSize is int && metaSize > 0) {
      return metaSize;
    }

    // 如果元数据没有，从本地文件读取
    final title = _getProperty(item, 'title', defaultValue: '');
    final relativePath = parentPath.isEmpty ? title : '$parentPath/$title';

    try {
      final downloadDir = await DownloadPathService.getDownloadDirectory();
      final file = File('${downloadDir.path}/${widget.work.id}/$relativePath');

      if (await file.exists()) {
        return await file.length();
      }
    } catch (e) {
      // 忽略错误
    }

    return null;
  }

  // 播放音频文件（从本地）
  Future<void> _playAudioFile(dynamic audioFile, String parentPath) async {
    final hash = _getProperty(audioFile, 'hash');
    final title = _getProperty(audioFile, 'title', defaultValue: '未知');

    if (hash == null) {
      SnackBarUtil.showError(context, '无法播放音频：缺少文件标识');
      return;
    }

    // 获取本地文件路径
    final downloadDir = await DownloadPathService.getDownloadDirectory();
    final relativePath = parentPath.isEmpty ? title : '$parentPath/$title';
    final localPath = '${downloadDir.path}/${widget.work.id}/$relativePath';
    final localFile = File(localPath);

    if (!await localFile.exists()) {
      SnackBarUtil.showError(context, '音频文件不存在');
      return;
    }

    // 获取作品封面URL（用于播放器显示）
    String? coverUrl;
    try {
      final coverFile = File('${downloadDir.path}/${widget.work.id}/cover.jpg');
      if (await coverFile.exists()) {
        coverUrl = 'file://${coverFile.path}';
      }
    } catch (e) {
      // 封面不存在，忽略
    }

    // 获取同一目录下的所有本地音频文件
    final audioFiles = _getAudioFilesFromSameDirectory(parentPath);

    final currentIndex =
        audioFiles.indexWhere((file) => _getProperty(file, 'hash') == hash);

    if (currentIndex == -1) {
      SnackBarUtil.showError(context, '无法找到音频文件: $title');
      return;
    }

    // 构建播放队列（仅使用本地文件）
    final List<AudioTrack> audioTracks = [];
    for (final file in audioFiles) {
      final fileHash = _getProperty(file, 'hash');
      final fileTitle = _getProperty(file, 'title', defaultValue: '未知');

      if (fileHash == null) continue;

      // 获取本地文件路径
      final fileRelativePath =
          parentPath.isEmpty ? fileTitle : '$parentPath/$fileTitle';
      final filePath =
          '${downloadDir.path}/${widget.work.id}/$fileRelativePath';
      final file2 = File(filePath);

      if (await file2.exists()) {
        // 使用 file:// 协议的本地路径
        final audioUrl = 'file://$filePath';

        // 获取声优信息
        final vaNames = widget.work.vas?.map((va) => va.name).toList() ?? [];
        final artistInfo = vaNames.isNotEmpty ? vaNames.join(', ') : null;

        audioTracks.add(AudioTrack(
          id: fileHash,
          url: audioUrl,
          title: fileTitle,
          artist: artistInfo,
          album: widget.work.title,
          artworkUrl: coverUrl,
          duration: _getProperty(file, 'duration') != null
              ? Duration(
                  milliseconds: (_getProperty(file, 'duration') * 1000).round())
              : null,
          workId: widget.work.id,
          hash: fileHash,
        ));
      }
    }

    if (audioTracks.isEmpty) {
      SnackBarUtil.showError(context, '没有找到可播放的音频文件');
      return;
    }

    // 播放音频队列，从当前选择的文件开始
    final adjustedIndex = audioTracks.indexWhere((track) => track.hash == hash);
    final startIndex = adjustedIndex != -1 ? adjustedIndex : 0;

    ref.read(audioPlayerControllerProvider.notifier).playTracks(
          audioTracks,
          startIndex: startIndex,
        );

    SnackBarUtil.showInfo(
        context, '正在播放: $title (${startIndex + 1}/${audioTracks.length})');
  }

  // 获取同一目录下的所有音频文件（不递归子文件夹）
  List<dynamic> _getAudioFilesFromSameDirectory(String targetPath) {
    final List<dynamic> audioFiles = [];

    // 如果是根目录
    if (targetPath.isEmpty) {
      for (final item in _localFiles) {
        if (item is Map<String, dynamic> && FileIconUtils.isAudioFile(item)) {
          audioFiles.add(item);
        }
      }
      return audioFiles;
    }

    // 查找目标路径对应的文件夹
    List<dynamic>? findFolderByPath(List<dynamic> items, String currentPath) {
      for (final item in items) {
        if (_getProperty(item, 'type', defaultValue: '') == 'folder') {
          final itemPath = _getItemPath(currentPath, item);

          if (itemPath == targetPath) {
            final children = _getProperty(item, 'children') as List<dynamic>?;
            return children;
          }

          final children = _getProperty(item, 'children') as List<dynamic>?;
          if (children != null) {
            final result = findFolderByPath(children, itemPath);
            if (result != null) return result;
          }
        }
      }
      return null;
    }

    final folderContents = findFolderByPath(_localFiles, '');

    if (folderContents != null) {
      for (final item in folderContents) {
        if (item is Map<String, dynamic> && FileIconUtils.isAudioFile(item)) {
          audioFiles.add(item);
        }
      }
    }

    return audioFiles;
  }

  // 辅助方法：判断文件名是否为音频格式
  // 手动加载字幕
  Future<void> _loadLyricManually(dynamic file) async {
    final title = _getProperty(file, 'title', defaultValue: '未知文件');

    final currentTrackAsync = ref.read(currentTrackProvider);
    final currentTrack = currentTrackAsync.value;

    if (currentTrack == null) {
      SnackBarUtil.showError(context, '当前没有播放的音频，无法加载字幕');
      return;
    }

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
                    Text('字幕文件：',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('当前音频：',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                    Text(currentTrack.title,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '注意：切换到其他音频时，字幕将自动恢复为默认匹配方式。',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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

    try {
      await ref.read(lyricControllerProvider.notifier).loadLyricManually(
            file,
            workId: widget.work.id,
          );
      SnackBarUtil.showSuccess(context, '字幕加载成功：$title');
    } catch (e) {
      SnackBarUtil.showError(context, '字幕加载失败：$e');
    }
  }

  // 预览图片文件（从本地）
  Future<void> _previewImageFile(dynamic file) async {
    final downloadDir = await DownloadPathService.getDownloadDirectory();
    final workPath = '${downloadDir.path}/${widget.work.id}';

    final imageFiles = _getImageFilesFromCurrentDirectory();
    final currentIndex = imageFiles.indexWhere(
        (f) => _getProperty(f, 'hash') == _getProperty(file, 'hash'));

    if (currentIndex == -1) {
      SnackBarUtil.showError(context, '无法找到图片文件');
      return;
    }

    final List<Map<String, String>> imageItems = [];
    for (final f in imageFiles) {
      final hash = _getProperty(f, 'hash', defaultValue: '');
      final title = _getProperty(f, 'title', defaultValue: '未知图片');

      final filePath = await _findFileFullPath(f, _localFiles, '');
      if (filePath != null) {
        final localPath = '$workPath/$filePath';
        final localFile = File(localPath);
        if (await localFile.exists()) {
          imageItems
              .add({'url': 'file://$localPath', 'title': title, 'hash': hash});
        }
      }
    }

    if (imageItems.isEmpty) {
      SnackBarUtil.showError(context, '没有找到可预览的图片');
      return;
    }

    final adjustedIndex = imageItems
        .indexWhere((item) => item['hash'] == _getProperty(file, 'hash'));

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ImageGalleryScreen(
          images: imageItems,
          initialIndex: adjustedIndex != -1 ? adjustedIndex : 0,
          workId: widget.work.id,
        ),
      ),
    );
  }

  List<dynamic> _getImageFilesFromCurrentDirectory() {
    final List<dynamic> imageFiles = [];

    void extractImageFiles(List<dynamic> items) {
      for (final item in items) {
        if (FileIconUtils.isImageFile(item)) {
          imageFiles.add(item);
        } else if (_getProperty(item, 'type', defaultValue: '') == 'folder') {
          final children = _getProperty(item, 'children') as List<dynamic>?;
          if (children != null) {
            extractImageFiles(children);
          }
        }
      }
    }

    if (_localFiles.isNotEmpty) {
      extractImageFiles(_localFiles);
    }

    return imageFiles;
  }

  Future<String?> _findFileFullPath(
      dynamic targetFile, List<dynamic> items, String parentPath) async {
    for (final item in items) {
      final type = _getProperty(item, 'type', defaultValue: '');
      final title = _getProperty(item, 'title', defaultValue: 'unknown');

      if (type == 'folder') {
        final children = _getProperty(item, 'children') as List<dynamic>?;
        if (children != null) {
          final folderPath = parentPath.isEmpty ? title : '$parentPath/$title';
          final result =
              await _findFileFullPath(targetFile, children, folderPath);
          if (result != null) return result;
        }
      } else {
        if (_getProperty(item, 'hash') == _getProperty(targetFile, 'hash')) {
          return parentPath.isEmpty ? title : '$parentPath/$title';
        }
      }
    }
    return null;
  }

  Future<void> _previewTextFile(dynamic file) async {
    final hash = _getProperty(file, 'hash');
    final title = _getProperty(file, 'title', defaultValue: '未知文本');

    if (hash == null) {
      SnackBarUtil.showError(context, '无法预览文本：缺少文件标识');
      return;
    }

    final filePath = await _findFileFullPath(file, _localFiles, '');
    if (filePath == null) {
      SnackBarUtil.showError(context, '无法找到文件路径');
      return;
    }

    final downloadDir = await DownloadPathService.getDownloadDirectory();
    final localPath = '${downloadDir.path}/${widget.work.id}/$filePath';
    final localFile = File(localPath);

    if (!await localFile.exists()) {
      SnackBarUtil.showError(context, '文件不存在：$title');
      return;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TextPreviewScreen(
          textUrl: 'file://$localPath',
          title: title,
          workId: widget.work.id,
          hash: hash,
        ),
      ),
    );
  }

  Future<void> _previewPdfFile(dynamic file) async {
    final hash = _getProperty(file, 'hash');
    final title = _getProperty(file, 'title', defaultValue: '未知PDF');

    if (hash == null) {
      SnackBarUtil.showError(context, '无法预览PDF：缺少文件标识');
      return;
    }

    final filePath = await _findFileFullPath(file, _localFiles, '');
    if (filePath == null) {
      SnackBarUtil.showError(context, '无法找到文件路径');
      return;
    }

    final downloadDir = await DownloadPathService.getDownloadDirectory();
    final localPath = '${downloadDir.path}/${widget.work.id}/$filePath';
    final localFile = File(localPath);

    if (!await localFile.exists()) {
      SnackBarUtil.showError(context, '文件不存在：$title');
      return;
    }

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
  }

  Future<void> _playVideoWithSystemPlayer(dynamic videoFile) async {
    final hash = _getProperty(videoFile, 'hash');

    if (hash == null) {
      SnackBarUtil.showError(context, '无法播放视频：缺少文件标识');
      return;
    }

    final filePath = await _findFileFullPath(videoFile, _localFiles, '');
    if (filePath == null) {
      SnackBarUtil.showError(context, '无法找到文件路径');
      return;
    }

    final downloadDir = await DownloadPathService.getDownloadDirectory();
    final localPath = '${downloadDir.path}/${widget.work.id}/$filePath';
    final localFile = File(localPath);

    if (!await localFile.exists()) {
      SnackBarUtil.showError(context, '视频文件不存在');
      return;
    }

    try {
      // 使用 OpenFilex 打开本地视频文件（支持 iOS/Android 沙盒路径）
      final result = await OpenFilex.open(localPath);

      if (result.type != ResultType.done) {
        // 打开失败，显示错误信息
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => ResponsiveAlertDialog(
              title: const Text('无法打开视频'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('错误信息: ${result.message}'),
                    const SizedBox(height: 12),
                    const Text('系统无法找到支持的视频播放器。'),
                    const SizedBox(height: 8),
                    const Text('请安装视频播放器应用（如 VLC、MX Player 等）'),
                    const SizedBox(height: 12),
                    const Text('文件路径：'),
                    SelectableText(localPath,
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      SnackBarUtil.showError(context, '打开视频文件时出错: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
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
              onPressed: _loadLocalFiles,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_localFiles.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              '没有已下载的文件',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
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
                    '离线文件',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _showTranslation = !_showTranslation;
                      });
                    },
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
                          Icon(
                            Icons.g_translate,
                            size: 16,
                            color: _showTranslation
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.7),
                          ),
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
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 文件树列表
          ..._buildFileTree(_localFiles, ''),
        ],
      ),
    );
  }

  // 递归构建文件树
  List<Widget> _buildFileTree(List<dynamic> items, String parentPath,
      {int level = 0}) {
    final List<Widget> widgets = [];

    for (final item in items) {
      final type = _getProperty(item, 'type', defaultValue: '');
      final originalTitle = _getProperty(item, 'title', defaultValue: '未知文件');
      final title = _getDisplayName(originalTitle); // 使用翻译后的名称
      final isFolder = type == 'folder';
      final children = _getProperty(item, 'children') as List<dynamic>?;
      final itemPath = _getItemPath(parentPath, item);
      final isExpanded = _expandedFolders.contains(itemPath);
      final isTranslating = _translatingItems.contains(originalTitle);

      // 如果启用翻译且该项未翻译，自动翻译
      if (_showTranslation &&
          !_translationCache.containsKey(originalTitle) &&
          !isTranslating) {
        _translateItem(originalTitle);
      }

      // 文件/文件夹项
      widgets.add(
        InkWell(
          onTap: () {
            if (isFolder) {
              _toggleFolder(itemPath);
            } else {
              _handleFileTap(item, title, parentPath);
            }
          },
          child: Padding(
            padding: EdgeInsets.only(
              left: 8.0 + (level * 20.0),
              right: 8.0,
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
                // 文件图标（带字幕库匹配标记）
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
                      // 字幕库匹配标记（音频文件）
                      if (type == 'audio' &&
                          _audioWithLibrarySubtitles.contains(originalTitle))
                        Positioned(
                          left: 0,
                          top: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.subtitles,
                              color: Colors.blue[600],
                              size: 13,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // 文件名 + 时长 + 文件大小
                Expanded(
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
                      // 显示文件大小
                      if (!isFolder)
                        FutureBuilder<int?>(
                          future: _getFileSize(item, parentPath),
                          builder: (context, snapshot) {
                            // 获取文件大小
                            final fileSize = snapshot.hasData
                                ? _formatFileSize(snapshot.data)
                                : '';

                            if (fileSize.isEmpty) {
                              return const SizedBox.shrink();
                            }

                            return Text(
                              fileSize,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
                // 操作按钮
                if (type == 'audio' ||
                    type == 'video' ||
                    FileIconUtils.isImageFile(item) ||
                    FileIconUtils.isTextFile(item) ||
                    FileIconUtils.isPdfFile(item) ||
                    !isFolder)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 字幕加载按钮（仅字幕文件显示）
                      if (FileIconUtils.isTextFile(item) &&
                          FileIconUtils.isLyricFile(originalTitle))
                        IconButton(
                          onPressed: () => _loadLyricManually(item),
                          icon: const Icon(Icons.subtitles),
                          color: Colors.orange,
                          tooltip: '加载为字幕',
                          iconSize: 20,
                        ),
                      // 删除按钮
                      IconButton(
                        onPressed: () => _deleteFile(item, parentPath),
                        icon: const Icon(Icons.delete_outline),
                        color: Colors.red.shade400,
                        tooltip: '删除',
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

  // 获取显示的名称（根据翻译状态）
  String _getDisplayName(String originalName) {
    if (_showTranslation && _translationCache.containsKey(originalName)) {
      return _translationCache[originalName]!;
    }
    return originalName;
  }

  // 按需翻译单个项目
  Future<void> _translateItem(String originalName) async {
    if (_translationCache.containsKey(originalName) ||
        _translatingItems.contains(originalName)) {
      return;
    }

    setState(() {
      _translatingItems.add(originalName);
    });

    try {
      final translationService = TranslationService();
      final translated = await translationService.translate(
        originalName,
        sourceLang: 'ja',
      );

      setState(() {
        _translationCache[originalName] = translated;
        _translatingItems.remove(originalName);
      });
    } catch (e) {
      print('[OfflineFileExplorer] 翻译失败: $e');
      setState(() {
        _translatingItems.remove(originalName);
      });
    }
  }

  // 处理文件点击
  void _handleFileTap(dynamic file, String title, String parentPath) {
    if (FileIconUtils.isAudioFile(file)) {
      _playAudioFile(file, parentPath);
    } else if (FileIconUtils.isVideoFile(file)) {
      _playVideoWithSystemPlayer(file);
    } else if (FileIconUtils.isImageFile(file)) {
      _previewImageFile(file);
    } else if (FileIconUtils.isPdfFile(file)) {
      _previewPdfFile(file);
    } else if (FileIconUtils.isTextFile(file)) {
      _previewTextFile(file);
    } else {
      SnackBarUtil.showInfo(context, '暂不支持打开此类型文件: $title');
    }
  }

  // 删除单个文件
  Future<void> _deleteFile(dynamic file, String parentPath) async {
    final title = _getProperty(file, 'title', defaultValue: '未知文件');
    final relativePath = parentPath.isEmpty ? title : '$parentPath/$title';

    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ResponsiveAlertDialog(
        title: const Text('确认删除'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('确定要删除这个文件吗？'),
            const SizedBox(height: 12),
            Text(
              relativePath,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      // 显示加载指示器
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      // 删除文件
      await DownloadService.instance.deleteFile(widget.work.id, relativePath);

      // 关闭加载指示器
      if (mounted) {
        Navigator.of(context).pop();
      }

      // 重新加载文件列表
      await _loadLocalFiles();

      // 显示成功消息
      if (mounted) {
        SnackBarUtil.showSuccess(context, '已删除: $title');
      }
    } catch (e) {
      // 关闭加载指示器
      if (mounted) {
        Navigator.of(context).pop();
      }

      // 显示错误消息
      if (mounted) {
        SnackBarUtil.showError(context, '删除失败: $e');
      }
    }
  }
}
