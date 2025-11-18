import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;

import '../services/cache_service.dart';
import '../services/translation_service.dart';
import '../services/subtitle_library_service.dart';
import '../utils/snackbar_util.dart';
import 'scrollable_appbar.dart';

/// 文本预览屏幕
class TextPreviewScreen extends StatefulWidget {
  final String textUrl;
  final String title;
  final int? workId;
  final String? hash;
  final VoidCallback? onSavedToLibrary;

  const TextPreviewScreen({
    super.key,
    required this.textUrl,
    required this.title,
    this.workId,
    this.hash,
    this.onSavedToLibrary,
  });

  @override
  State<TextPreviewScreen> createState() => _TextPreviewScreenState();
}

class _TextPreviewScreenState extends State<TextPreviewScreen> {
  bool _isLoading = true;
  String? _content;
  String? _translatedContent;
  String? _errorMessage;
  final ScrollController _scrollController = ScrollController();
  double _scrollProgress = 0.0;
  bool _showTranslation = false;
  bool _isTranslating = false;
  String _translationProgress = '';
  bool _isEditMode = false;
  late TextEditingController _textController;
  late TextEditingController _translatedTextController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _translatedTextController = TextEditingController();
    _loadTextContent();
    _scrollController.addListener(_updateScrollProgress);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollProgress);
    _scrollController.dispose();
    _textController.dispose();
    _translatedTextController.dispose();
    super.dispose();
  }

  void _updateScrollProgress() {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      setState(() {
        _scrollProgress = maxScroll > 0 ? currentScroll / maxScroll : 0.0;
      });
    }
  }

  void _showSaveOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('保存到本地'),
              subtitle: const Text('选择目录保存文件'),
              onTap: () {
                Navigator.pop(context);
                _saveToLocal();
              },
            ),
            ListTile(
              leading: const Icon(Icons.library_books),
              title: const Text('保存到字幕库'),
              subtitle: const Text('保存到字幕库的“已保存”目录'),
              onTap: () {
                Navigator.pop(context);
                _saveToSubtitleLibrary();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _saveToLocal() async {
    // 获取当前显示的内容（可能是编辑后的）
    final contentToSave = _getCurrentContent();
    if (contentToSave == null || contentToSave.isEmpty) {
      SnackBarUtil.showWarning(context, '没有可保存的内容');
      return;
    }

    try {
      // 选择保存目录
      final directoryPath = await FilePicker.platform.getDirectoryPath();
      if (directoryPath == null) return;

      // 生成文件名
      String fileName = widget.title;
      if (!fileName.contains('.')) {
        fileName = '$fileName.txt';
      }

      // 检查文件是否已存在，如果存在则添加序号
      String finalPath = path.join(directoryPath, fileName);
      int counter = 1;
      while (await File(finalPath).exists()) {
        final nameWithoutExt = path.basenameWithoutExtension(fileName);
        final ext = path.extension(fileName);
        finalPath = path.join(directoryPath, '${nameWithoutExt}_$counter$ext');
        counter++;
      }

      // 写入文件
      final file = File(finalPath);
      await file.writeAsString(contentToSave);

      SnackBarUtil.showSuccess(context, '文件已保存到：$finalPath');
    } catch (e) {
      SnackBarUtil.showError(context, '保存失败: $e');
    }
  }

  Future<void> _saveToSubtitleLibrary() async {
    // 获取当前显示的内容（可能是编辑后的）
    final contentToSave = _getCurrentContent();
    if (contentToSave == null || contentToSave.isEmpty) {
      SnackBarUtil.showWarning(context, '没有可保存的内容');
      return;
    }

    try {
      // 获取字幕库目录
      final libraryDir =
          await SubtitleLibraryService.getSubtitleLibraryDirectory();

      // 创建“已保存”目录
      final savedDir = Directory(path.join(libraryDir.path, '已保存'));
      if (!await savedDir.exists()) {
        await savedDir.create();
      }

      // 生成文件名
      String fileName = widget.title;
      if (!fileName.contains('.')) {
        fileName = '$fileName.txt';
      }

      // 检查文件是否已存在，如果存在则添加序号
      String finalPath = path.join(savedDir.path, fileName);
      int counter = 1;
      while (await File(finalPath).exists()) {
        final nameWithoutExt = path.basenameWithoutExtension(fileName);
        final ext = path.extension(fileName);
        finalPath = path.join(savedDir.path, '${nameWithoutExt}_$counter$ext');
        counter++;
      }

      // 写入文件
      final file = File(finalPath);
      await file.writeAsString(contentToSave);

      SnackBarUtil.showSuccess(context, '已保存到字幕库');

      // 触发字幕库重载回调
      widget.onSavedToLibrary?.call();
    } catch (e) {
      SnackBarUtil.showError(context, '保存失败: $e');
    }
  }

  String? _getCurrentContent() {
    if (_showTranslation && _translatedContent != null) {
      return _isEditMode ? _translatedTextController.text : _translatedContent;
    } else {
      return _isEditMode ? _textController.text : _content;
    }
  }

  Future<void> _loadTextContent() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 优先检查是否是本地文件（file:// 协议）
      if (widget.textUrl.startsWith('file://')) {
        final localPath = widget.textUrl.substring(7); // 移除 'file://' 前缀
        final localFile = File(localPath);

        if (await localFile.exists()) {
          final content = await localFile.readAsString();
          setState(() {
            _content = content;
            _textController.text = content;
            _isLoading = false;
          });
          return;
        } else {
          setState(() {
            _errorMessage = '本地文件不存在';
            _isLoading = false;
          });
          return;
        }
      }

      if (widget.workId != null &&
          widget.hash != null &&
          widget.hash!.isNotEmpty) {
        final cachedContent = await CacheService.getCachedTextContent(
          workId: widget.workId!,
          hash: widget.hash!,
          fileName: null, // TextPreviewScreen doesn't track fileName
        );

        if (cachedContent != null) {
          setState(() {
            _content = cachedContent;
            _textController.text = cachedContent;
            _isLoading = false;
          });
          return;
        }
      }

      final dio = Dio();
      final response = await dio.get(
        widget.textUrl,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200) {
        final content = response.data as String;

        if (widget.workId != null &&
            widget.hash != null &&
            widget.hash!.isNotEmpty) {
          await CacheService.cacheTextContent(
            workId: widget.workId!,
            hash: widget.hash!,
            content: content,
          );
        }

        setState(() {
          _content = content;
          _textController.text = content;
          _isLoading = false;
        });
      } else {
        throw Exception(
            'HTTP ${response.statusCode}: ${response.statusMessage}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = '加载文本失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _translateContent() async {
    if (_content == null || _content!.isEmpty) return;

    setState(() {
      _isTranslating = true;
      _translationProgress = '准备翻译...';
    });

    try {
      final translationService = TranslationService();
      final translated = await translationService.translateLongText(
        _content!,
        onProgress: (current, total) {
          setState(() {
            _translationProgress = '翻译中 $current/$total';
          });
        },
      );

      setState(() {
        _translatedContent = translated;
        _translatedTextController.text = translated;
        _showTranslation = true;
        _isTranslating = false;
        _translationProgress = '';
      });
    } catch (e) {
      setState(() {
        _isTranslating = false;
        _translationProgress = '';
      });
      if (mounted) {
        SnackBarUtil.showError(context, '翻译失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ScrollableAppBar(
        title: Text(widget.title),
        actions: [
          if (_content != null && _content!.isNotEmpty)
            IconButton(
              icon: Icon(
                _isEditMode ? Icons.visibility : Icons.edit,
                color:
                    _isEditMode ? Theme.of(context).colorScheme.primary : null,
              ),
              onPressed: () {
                setState(() {
                  _isEditMode = !_isEditMode;
                });
              },
              tooltip: _isEditMode ? '预览模式' : '编辑模式',
            ),
          if (_content != null && _content!.isNotEmpty)
            IconButton(
              icon: _isTranslating
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    )
                  : Icon(
                      Icons.g_translate,
                      color: _showTranslation
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
              onPressed: _isTranslating
                  ? null
                  : () {
                      if (_translatedContent != null) {
                        setState(() {
                          _showTranslation = !_showTranslation;
                        });
                      } else {
                        _translateContent();
                      }
                    },
              tooltip: _showTranslation ? '显示原文' : '翻译内容',
            ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _showSaveOptions,
            tooltip: '保存',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
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
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadTextContent,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        LinearProgressIndicator(
          value: _scrollProgress,
          backgroundColor: Colors.grey[300],
          valueColor: AlwaysStoppedAnimation<Color>(
            Theme.of(context).colorScheme.primary,
          ),
          minHeight: 3,
        ),
        if (_isTranslating)
          Container(
            padding: const EdgeInsets.all(8),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(_translationProgress),
              ],
            ),
          ),
        Expanded(
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              child: _isEditMode
                  ? TextField(
                      controller: _showTranslation && _translatedContent != null
                          ? _translatedTextController
                          : _textController,
                      maxLines: null,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                      ),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: '编辑文本内容...',
                      ),
                    )
                  : SelectableText(
                      _showTranslation && _translatedContent != null
                          ? _translatedContent!
                          : _content ?? '',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => message;
}
