import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/work.dart';
import '../utils/string_utils.dart';

/// 离线文件浏览器 - 显示已下载的文件
/// 只显示硬盘上实际存在的文件，不显示未下载的文件
class OfflineFileExplorerWidget extends StatefulWidget {
  final Work work;
  final List<dynamic>? fileTree; // 从 work_metadata.json 中读取的文件树

  const OfflineFileExplorerWidget({
    super.key,
    required this.work,
    this.fileTree,
  });

  @override
  State<OfflineFileExplorerWidget> createState() =>
      _OfflineFileExplorerWidgetState();
}

class _OfflineFileExplorerWidgetState extends State<OfflineFileExplorerWidget> {
  final Set<String> _expandedFolders = {}; // 记录展开的文件夹路径
  final Map<String, bool> _fileExists = {}; // hash -> exists on disk
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkDownloadedFiles();
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
            return (item as dynamic).title ??
                defaultValue; // AudioFile 使用 title
          case 'hash':
            return (item as dynamic).hash ?? defaultValue;
          case 'children':
            return (item as dynamic).children ?? defaultValue;
          case 'size':
            return (item as dynamic).size ?? defaultValue;
          case 'mediaType':
            return (item as dynamic).type ?? defaultValue; // AudioFile 使用 type
          case 'duration':
            return null; // AudioFile 没有 duration 字段
          default:
            return defaultValue;
        }
      } catch (e) {
        return defaultValue;
      }
    }
  }

  // 检查文件是否在硬盘上存在
  Future<void> _checkDownloadedFiles() async {
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
      final appDir = await getApplicationDocumentsDirectory();
      final workDir = Directory('${appDir.path}/downloads/${widget.work.id}');

      if (!await workDir.exists()) {
        setState(() {
          _isLoading = false;
          _errorMessage = '作品文件夹不存在';
        });
        return;
      }

      void checkFiles(List<dynamic> items, String parentPath) {
        for (final item in items) {
          final type = _getProperty(item, 'type', defaultValue: '');
          final hash = _getProperty(item, 'hash');
          if (type != 'folder' && hash != null) {
            final title = _getProperty(item, 'title', defaultValue: 'unknown');
            // 使用相对路径检查文件
            final relativePath =
                parentPath.isEmpty ? title : '$parentPath/$title';
            final file = File('${workDir.path}/$relativePath');
            _fileExists[hash] = file.existsSync();
          }
          final children = _getProperty(item, 'children') as List<dynamic>?;
          if (children != null && children.isNotEmpty) {
            final title = _getProperty(item, 'title', defaultValue: 'unknown');
            final folderPath =
                parentPath.isEmpty ? title : '$parentPath/$title';
            checkFiles(children, folderPath);
          }
        }
      }

      checkFiles(widget.fileTree!, '');

      // 自动展开主文件夹
      _identifyAndExpandMainFolder();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '检查文件失败: $e';
      });
    }
  }

  // 识别并展开主文件夹
  void _identifyAndExpandMainFolder() {
    if (widget.fileTree == null || widget.fileTree!.isEmpty) return;

    // 如果只有一个根文件夹，自动展开
    if (widget.fileTree!.length == 1) {
      final item = widget.fileTree![0];
      final type = _getProperty(item, 'type', defaultValue: '');
      if (type == 'folder') {
        final title = _getProperty(item, 'title', defaultValue: '');
        _expandedFolders.add(title);
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
  String _formatSize(dynamic size) {
    if (size == null) return '';
    final bytes = size is int ? size : (size is double ? size.toInt() : 0);
    return formatBytes(bytes);
  }

  // 格式化持续时间
  String _formatDuration(dynamic durationValue) {
    if (durationValue == null) return '';

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

  // 打开文件 - 简化版本，暂时只显示文件信息
  Future<void> _openFile(dynamic file) async {
    final title = _getProperty(file, 'title', defaultValue: '未知');
    final hash = _getProperty(file, 'hash');

    if (hash == null) {
      _showError('无法打开文件：缺少文件标识');
      return;
    }

    final appDir = await getApplicationDocumentsDirectory();
    final filePath = '${appDir.path}/downloads/${widget.work.id}/$title';
    final localFile = File(filePath);

    if (!await localFile.exists()) {
      _showError('文件不存在：$title');
      return;
    }

    // TODO: 实现离线文件预览
    // 目前只显示文件信息
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('文件信息'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('文件名：$title'),
            const SizedBox(height: 8),
            Text('路径：$filePath'),
            const SizedBox(height: 8),
            Text('大小：${_formatSize(_getProperty(file, 'size'))}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // 根据文件类型返回图标
  IconData _getFileIconForType(String type) {
    switch (type.toLowerCase()) {
      case 'audio':
        return Icons.audiotrack;
      case 'image':
        return Icons.image;
      case 'text':
        return Icons.description;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'video':
        return Icons.videocam;
      default:
        return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.fileTree == null || widget.fileTree!.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '没有文件信息',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    // 检查是否有已下载的文件
    final hasDownloadedFiles = _fileExists.values.any((exists) => exists);
    if (!hasDownloadedFiles) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_off, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                '没有已下载的文件',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: _buildFileTree(widget.fileTree!, ''),
    );
  }

  List<Widget> _buildFileTree(List<dynamic> items, String parentPath) {
    final widgets = <Widget>[];

    for (final item in items) {
      final type = _getProperty(item, 'type', defaultValue: '');
      final title = _getProperty(item, 'title', defaultValue: 'unknown');
      final itemPath = _getItemPath(parentPath, item);

      if (type == 'folder') {
        final children = _getProperty(item, 'children') as List<dynamic>?;
        final isExpanded = _expandedFolders.contains(itemPath);

        // 检查文件夹是否包含已下载的文件
        bool hasDownloaded = false;
        if (children != null) {
          hasDownloaded = _folderHasDownloadedFiles(children);
        }

        // 只显示包含已下载文件的文件夹
        if (!hasDownloaded) continue;

        widgets.add(
          InkWell(
            onTap: () => _toggleFolder(itemPath),
            child: Padding(
              padding: EdgeInsets.only(
                left: parentPath.split('/').length * 16.0,
                top: 8,
                bottom: 8,
              ),
              child: Row(
                children: [
                  Icon(
                    isExpanded ? Icons.folder_open : Icons.folder,
                    color: Colors.amber,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        );

        if (isExpanded && children != null) {
          widgets.addAll(_buildFileTree(children, itemPath));
        }
      } else {
        // 文件项
        final hash = _getProperty(item, 'hash');
        final exists = hash != null && (_fileExists[hash] ?? false);

        // 只显示已下载的文件
        if (!exists) continue;

        final mediaType = _getProperty(item, 'mediaType', defaultValue: type);
        final duration = _getProperty(item, 'duration');
        final size = _getProperty(item, 'size');
        final icon = _getFileIconForType(mediaType);

        widgets.add(
          InkWell(
            onTap: () => _openFile(item),
            child: Padding(
              padding: EdgeInsets.only(
                left: parentPath.split('/').length * 16.0 + 8,
                top: 8,
                bottom: 8,
              ),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontSize: 14),
                        ),
                        if (duration != null || size != null)
                          Text(
                            [
                              if (duration != null) _formatDuration(duration),
                              if (size != null) _formatSize(size),
                            ].where((s) => s.isNotEmpty).join(' • '),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
            ),
          ),
        );
      }
    }

    return widgets;
  }

  // 检查文件夹是否包含已下载的文件（递归）
  bool _folderHasDownloadedFiles(List<dynamic> items) {
    for (final item in items) {
      final type = _getProperty(item, 'type', defaultValue: '');
      if (type == 'folder') {
        final children = _getProperty(item, 'children') as List<dynamic>?;
        if (children != null && _folderHasDownloadedFiles(children)) {
          return true;
        }
      } else {
        final hash = _getProperty(item, 'hash');
        if (hash != null && (_fileExists[hash] ?? false)) {
          return true;
        }
      }
    }
    return false;
  }
}
