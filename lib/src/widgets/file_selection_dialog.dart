import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/work.dart';
import '../services/download_service.dart';
import '../utils/string_utils.dart';
import '../utils/file_icon_utils.dart';
import '../providers/auth_provider.dart';

class FileSelectionDialog extends ConsumerStatefulWidget {
  final Work work;

  const FileSelectionDialog({
    super.key,
    required this.work,
  });

  @override
  ConsumerState<FileSelectionDialog> createState() =>
      _FileSelectionDialogState();
}

class _FileSelectionDialogState extends ConsumerState<FileSelectionDialog> {
  final Map<String, bool> _selectedFiles = {}; // hash -> selected
  final Map<String, bool> _downloadedFiles = {}; // hash -> downloaded
  final Set<String> _expandedFolders = {}; // 展开的文件夹路径
  bool _isCheckingDownloads = true;

  @override
  void initState() {
    super.initState();
    _initializeSelection();
    _checkDownloadedFiles();
  }

  void _initializeSelection() {
    void processChildren(List<AudioFile> children) {
      for (final file in children) {
        if (file.type == 'file' && file.hash != null) {
          _selectedFiles[file.hash!] = false;
          _downloadedFiles[file.hash!] = false;
        }
        if (file.children != null) {
          processChildren(file.children!);
        }
      }
    }

    if (widget.work.children != null) {
      processChildren(widget.work.children!);
    }
  }

  // 检查已下载的文件
  Future<void> _checkDownloadedFiles() async {
    final downloadService = DownloadService.instance;

    for (final hash in _downloadedFiles.keys) {
      final filePath =
          await downloadService.getDownloadedFilePath(widget.work.id, hash);
      if (filePath != null) {
        _downloadedFiles[hash] = true;
      }
    }

    if (mounted) {
      setState(() {
        _isCheckingDownloads = false;
      });
    }
  }

  // 生成文件/文件夹的唯一路径
  String _getItemPath(String parentPath, AudioFile item) {
    final title = item.title;
    return parentPath.isEmpty ? title : '$parentPath/$title';
  }

  // 切换文件夹展开/折叠
  void _toggleFolder(String path) {
    setState(() {
      if (_expandedFolders.contains(path)) {
        _expandedFolders.remove(path);
      } else {
        _expandedFolders.add(path);
      }
    });
  }

  // 切换文件选中状态
  void _toggleFile(String hash) {
    setState(() {
      _selectedFiles[hash] = !(_selectedFiles[hash] ?? false);
    });
  }

  // 切换文件夹选中状态（递归）
  void _toggleFolderSelection(String path, bool selected) {
    void selectInChildren(List<AudioFile> items, String parentPath) {
      for (final item in items) {
        final itemPath = _getItemPath(parentPath, item);

        if (item.type == 'file' && item.hash != null) {
          // 只选择未下载的文件
          final isDownloaded = _downloadedFiles[item.hash!] ?? false;
          if (!isDownloaded) {
            _selectedFiles[item.hash!] = selected;
          }
        } else if (item.type == 'folder' && item.children != null) {
          selectInChildren(item.children!, itemPath);
        }
      }
    }

    // 找到目标文件夹并递归选择其中的所有文件
    void findAndSelect(List<AudioFile> items, String currentPath) {
      for (final item in items) {
        final itemPath = _getItemPath(currentPath, item);

        if (itemPath == path && item.children != null) {
          selectInChildren(item.children!, itemPath);
          return;
        }

        if (item.type == 'folder' && item.children != null) {
          findAndSelect(item.children!, itemPath);
        }
      }
    }

    setState(() {
      if (widget.work.children != null) {
        findAndSelect(widget.work.children!, '');
      }
    });
  }

  // 全选/取消全选
  void _toggleSelectAll() {
    // 只考虑未下载的文件
    final availableFiles = _selectedFiles.keys
        .where((hash) => !(_downloadedFiles[hash] ?? false))
        .toList();

    if (availableFiles.isEmpty) return;

    final allSelected =
        availableFiles.every((hash) => _selectedFiles[hash] ?? false);
    setState(() {
      for (final hash in availableFiles) {
        _selectedFiles[hash] = !allSelected;
      }
    });
  }

  // 获取文件夹的选中状态（全选/部分选中/未选中）
  bool? _getFolderSelectionState(AudioFile folder) {
    if (folder.children == null || folder.children!.isEmpty) {
      return false;
    }

    int selectedCount = 0;
    int totalCount = 0;

    void countSelection(List<AudioFile> items) {
      for (final item in items) {
        if (item.type == 'file' && item.hash != null) {
          // 排除已下载的文件
          final isDownloaded = _downloadedFiles[item.hash!] ?? false;
          if (!isDownloaded) {
            totalCount++;
            if (_selectedFiles[item.hash!] ?? false) {
              selectedCount++;
            }
          }
        }
        if (item.children != null) {
          countSelection(item.children!);
        }
      }
    }

    countSelection(folder.children!);

    if (totalCount == 0) {
      return false; // 文件夹中所有文件都已下载
    } else if (selectedCount == 0) {
      return false;
    } else if (selectedCount == totalCount) {
      return true;
    } else {
      return null; // 部分选中
    }
  }

  // 获取选中的文件及其相对路径
  Map<AudioFile, String> _getSelectedFilesWithPaths() {
    final selected = <AudioFile, String>{};

    void processChildren(List<AudioFile> children, String parentPath) {
      for (final file in children) {
        if (file.type == 'file') {
          if (_selectedFiles[file.hash ?? ''] ?? false) {
            selected[file] = parentPath;
          }
        } else if (file.children != null) {
          // 文件夹，递归处理子项
          final folderPath =
              parentPath.isEmpty ? file.title : '$parentPath/${file.title}';
          processChildren(file.children!, folderPath);
        }
      }
    }

    if (widget.work.children != null) {
      processChildren(widget.work.children!, '');
    }

    return selected;
  }

  List<AudioFile> _getSelectedFiles() {
    return _getSelectedFilesWithPaths().keys.toList();
  }

  void _startDownload() async {
    final selectedFilesWithPaths = _getSelectedFilesWithPaths();
    if (selectedFilesWithPaths.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请至少选择一个文件')),
        );
      }
      return;
    }

    final downloadService = DownloadService.instance;

    // 获取封面URL
    final authState = ref.read(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';
    final coverUrl = widget.work.getCoverImageUrl(host, token: token);

    // 保存作品元数据用于离线预览，包含完整文件树
    final workJson = widget.work.toJson();
    // 保留 children 字段用于离线文件浏览
    final workMetadata = Map<String, dynamic>.from(workJson);

    for (final entry in selectedFilesWithPaths.entries) {
      final file = entry.key;
      final relativePath = entry.value;

      // 构建完整的文件名（包含路径）
      final fullFileName =
          relativePath.isEmpty ? file.title : '$relativePath/${file.title}';

      await downloadService.addTask(
        workId: widget.work.id,
        workTitle: widget.work.title,
        fileName: fullFileName, // 使用包含路径的文件名
        downloadUrl: file.mediaDownloadUrl ?? '',
        hash: file.hash,
        totalBytes: file.size,
        workMetadata: workMetadata,
        coverUrl: coverUrl,
      );
    }

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('已添加 ${selectedFilesWithPaths.length} 个文件到下载队列')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    if (isLandscape) {
      // 横屏模式：紧凑布局，最大化文件列表空间
      return Dialog(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 紧凑标题栏：整合所有控制项
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.download,
                      color: theme.colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.work.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (!_isCheckingDownloads) ...[
                            const SizedBox(height: 2),
                            Text(
                              '已下载 ${_downloadedFiles.values.where((v) => v).length} · 已选择 ${_selectedFiles.values.where((v) => v).length}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer
                                    .withAlpha(179),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // 全选按钮
                    TextButton.icon(
                      icon: Icon(
                        Icons.select_all,
                        size: 16,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                      label: Text(
                        '全选',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      onPressed: _toggleSelectAll,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 下载按钮
                    FilledButton.icon(
                      onPressed: _startDownload,
                      icon: const Icon(Icons.download, size: 16),
                      label: Text('下载 (${_getSelectedFiles().length})'),
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.onPrimaryContainer,
                        foregroundColor: theme.colorScheme.primaryContainer,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 关闭按钮
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      color: theme.colorScheme.onPrimaryContainer,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                      tooltip: '关闭',
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // 文件列表：最大化显示空间
              Flexible(
                child: _isCheckingDownloads
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('正在检查已下载文件...'),
                          ],
                        ),
                      )
                    : widget.work.children == null ||
                            widget.work.children!.isEmpty
                        ? const Center(
                            child: Text('没有可下载的文件'),
                          )
                        : ListView(
                            children:
                                _buildFileTree(widget.work.children!, 0, ''),
                          ),
              ),
            ],
          ),
        ),
      );
    }

    // 竖屏模式：保持原有布局
    return Dialog(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
          maxWidth: 800,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.download,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '选择下载文件',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.work.title,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer
                                .withAlpha(179),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ],
              ),
            ),

            // Toolbar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.select_all, size: 18),
                    label: const Text('全选'),
                    onPressed: _toggleSelectAll,
                  ),
                  const Spacer(),
                  if (!_isCheckingDownloads) ...[
                    Text(
                      '已下载 ${_downloadedFiles.values.where((v) => v).length} 个',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.green[700],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 1,
                      height: 12,
                      color: theme.dividerColor,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '已选择 ${_selectedFiles.values.where((v) => v).length} 个',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(153),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // File List
            Flexible(
              child: _isCheckingDownloads
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('正在检查已下载文件...'),
                        ],
                      ),
                    )
                  : widget.work.children == null ||
                          widget.work.children!.isEmpty
                      ? const Center(
                          child: Text('没有可下载的文件'),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children:
                              _buildFileTree(widget.work.children!, 0, ''),
                        ),
            ),

            const Divider(height: 1),

            // Actions
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _startDownload,
                    icon: const Icon(Icons.download),
                    label: Text('下载 (${_getSelectedFiles().length})'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFileTree(
      List<AudioFile> files, int level, String parentPath) {
    final widgets = <Widget>[];
    final theme = Theme.of(context);

    for (final file in files) {
      final itemPath = _getItemPath(parentPath, file);

      if (file.type == 'folder' && file.children != null) {
        final isExpanded = _expandedFolders.contains(itemPath);
        final selectionState = _getFolderSelectionState(file);

        // 文件夹行
        widgets.add(
          InkWell(
            onTap: () => _toggleFolder(itemPath),
            child: Padding(
              padding: EdgeInsets.only(
                left: 4.0 + (level * 16.0),
                right: 4.0,
              ),
              child: Row(
                children: [
                  // 展开/折叠图标
                  SizedBox(
                    width: 32,
                    height: 40,
                    child: Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      color: theme.colorScheme.onSurface.withAlpha(153),
                      size: 20,
                    ),
                  ),
                  // 复选框
                  SizedBox(
                    width: 32,
                    height: 40,
                    child: Checkbox(
                      value: selectionState,
                      tristate: true,
                      onChanged: (value) {
                        _toggleFolderSelection(itemPath, value ?? false);
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  // 文件夹图标
                  Icon(
                    FileIconUtils.getFileIcon(file),
                    color: FileIconUtils.getFileIconColor(file),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  // 文件夹名称
                  Expanded(
                    child: Text(
                      file.title,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        // 如果展开,显示子项
        if (isExpanded) {
          widgets.addAll(_buildFileTree(file.children!, level + 1, itemPath));
        }
      } else if (file.type == 'file') {
        // 文件行
        final hash = file.hash ?? '';
        final isDownloaded = _downloadedFiles[hash] ?? false;
        final isSelected = _selectedFiles[hash] ?? false;

        widgets.add(
          InkWell(
            onTap: isDownloaded ? null : () => _toggleFile(hash),
            child: Padding(
              padding: EdgeInsets.only(
                left: 4.0 + (level * 16.0),
                right: 4.0,
              ),
              child: Row(
                children: [
                  // 占位（与文件夹的箭头对齐）
                  const SizedBox(width: 32, height: 40),
                  // 复选框或已下载标识
                  SizedBox(
                    width: 32,
                    height: 40,
                    child: isDownloaded
                        ? Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 20,
                          )
                        : Checkbox(
                            value: isSelected,
                            onChanged: (_) => _toggleFile(hash),
                          ),
                  ),
                  const SizedBox(width: 4),
                  // 文件图标
                  Icon(
                    FileIconUtils.getFileIcon(file),
                    color: FileIconUtils.getFileIconColor(file),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  // 文件名和大小
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                file.title,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: isDownloaded
                                      ? theme.colorScheme.onSurface
                                          .withAlpha(153)
                                      : null,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isDownloaded) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withAlpha(51),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '已下载',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.green[700],
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (file.size != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            formatBytes(file.size!),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withAlpha(153),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    return widgets;
  }
}
