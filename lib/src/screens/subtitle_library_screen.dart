import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import '../services/subtitle_library_service.dart';
import '../providers/settings_provider.dart';
import '../widgets/text_preview_screen.dart';

/// 字幕库界面
class SubtitleLibraryScreen extends ConsumerStatefulWidget {
  const SubtitleLibraryScreen({super.key});

  @override
  ConsumerState<SubtitleLibraryScreen> createState() =>
      _SubtitleLibraryScreenState();
}

class _SubtitleLibraryScreenState extends ConsumerState<SubtitleLibraryScreen> {
  List<Map<String, dynamic>> _files = [];
  bool _isLoading = true;
  String? _errorMessage;
  LibraryStats? _stats;
  final Set<String> _expandedFolders = {};

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final files = await SubtitleLibraryService.getSubtitleFiles();
      final stats = await SubtitleLibraryService.getStats();

      setState(() {
        _files = files;
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _importFile() async {
    final result = await SubtitleLibraryService.importSubtitleFile();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? Colors.green : Colors.red,
      ),
    );

    if (result.success) {
      _loadFiles();
    }
  }

  Future<void> _importFolder() async {
    final result = await SubtitleLibraryService.importFolder();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? Colors.green : Colors.red,
      ),
    );

    if (result.success) {
      _loadFiles();
    }
  }

  Future<void> _importArchive() async {
    final result = await SubtitleLibraryService.importArchive();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? Colors.green : Colors.red,
      ),
    );

    if (result.success) {
      _loadFiles();
    }
  }

  void _showImportOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: const Text('导入字幕文件'),
              subtitle: const Text('支持 .srt, .vtt, .lrc 等字幕格式'),
              onTap: () {
                Navigator.pop(context);
                _importFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder),
              title: const Text('导入文件夹'),
              subtitle: const Text('保留文件夹结构，仅导入字幕文件'),
              onTap: () {
                Navigator.pop(context);
                _importFolder();
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive),
              title: const Text('导入压缩包'),
              subtitle: const Text('支持无密码 ZIP 压缩包'),
              onTap: () {
                Navigator.pop(context);
                _importArchive();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showFileOptions(Map<String, dynamic> item, String path) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item['type'] == 'text')
              ListTile(
                leading: const Icon(Icons.visibility),
                title: const Text('预览'),
                onTap: () {
                  Navigator.pop(context);
                  _previewFile(path);
                },
              ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('打开'),
              onTap: () {
                Navigator.pop(context);
                _openFile(path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(context);
                _renameItem(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteItem(item);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _previewFile(String path) async {
    try {
      if (!mounted) return;

      // 使用 file:// 协议作为本地文件的 URL
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => TextPreviewScreen(
            title: path.split(Platform.pathSeparator).last,
            textUrl: 'file://$path',
            workId: null,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('预览失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openFile(String path) async {
    try {
      await OpenFilex.open(path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('打开失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _renameItem(Map<String, dynamic> item) async {
    final controller = TextEditingController(text: item['title']);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '新名称',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || newName == item['title']) {
      return;
    }

    final success = await SubtitleLibraryService.rename(item['path'], newName);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? '重命名成功' : '重命名失败'),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );

    if (success) {
      _loadFiles();
    }
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(
            '确定要删除 "${item['title']}" 吗？${item['type'] == 'folder' ? '\n\n此操作将删除文件夹内的所有内容。' : ''}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await SubtitleLibraryService.delete(item['path']);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? '删除成功' : '删除失败'),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );

    if (success) {
      _loadFiles();
    }
  }

  void _toggleFolder(String path) {
    setState(() {
      if (_expandedFolders.contains(path)) {
        _expandedFolders.remove(path);
      } else {
        _expandedFolders.add(path);
      }
    });
  }

  List<Widget> _buildFileTree(List<Map<String, dynamic>> items, int level) {
    final children = <Widget>[];

    for (final item in items) {
      final isFolder = item['type'] == 'folder';
      final path = item['path'] as String;
      final isExpanded = _expandedFolders.contains(path);

      children.add(
        InkWell(
          onTap: () {
            if (isFolder) {
              _toggleFolder(path);
            } else {
              _showFileOptions(item, path);
            }
          },
          child: Padding(
            padding: EdgeInsets.only(left: level * 16.0),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Row(
                children: [
                  if (isFolder)
                    Icon(
                      isExpanded ? Icons.folder_open : Icons.folder,
                      color: Colors.amber,
                      size: 20,
                    )
                  else
                    Icon(
                      Icons.text_snippet,
                      color: Colors.grey,
                      size: 20,
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['title'],
                          style: const TextStyle(fontSize: 14),
                        ),
                        if (!isFolder && item['size'] != null)
                          Text(
                            _formatSize(item['size']),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert, size: 18),
                    onPressed: () => _showFileOptions(item, path),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      if (isFolder && isExpanded && item['children'] != null) {
        children.addAll(_buildFileTree(item['children'], level + 1));
      }
    }

    return children;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听刷新触发器（例如下载路径更改时）
    ref.listen<int>(subtitleLibraryRefreshTriggerProvider, (previous, next) {
      if (previous != next) {
        _loadFiles();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('本地字幕库'),
        actions: [
          if (_stats != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Center(
                child: Text(
                  '${_stats!.totalFiles} 个文件 • ${_stats!.sizeFormatted}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showImportOptions,
        tooltip: '导入字幕',
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_errorMessage!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadFiles,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : _files.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.library_books_outlined,
                            size: 64,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '字幕库为空',
                            style: TextStyle(
                              fontSize: 18,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '点击右下角 + 按钮导入字幕',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadFiles,
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 80),
                        children: [
                          Container(
                            margin: const EdgeInsets.all(16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withOpacity(0.3),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '字幕库用于存放导入的外部字幕文件\n支持 .srt, .vtt, .lrc, .ass 等格式',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ..._buildFileTree(_files, 0),
                        ],
                      ),
                    ),
    );
  }
}
