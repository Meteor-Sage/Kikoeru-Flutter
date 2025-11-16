import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../services/cache_service.dart';
import '../services/translation_service.dart';
import 'scrollable_appbar.dart';

/// 文本预览屏幕
class TextPreviewScreen extends StatefulWidget {
  final String textUrl;
  final String title;
  final int? workId;
  final String? hash;

  const TextPreviewScreen({
    super.key,
    required this.textUrl,
    required this.title,
    this.workId,
    this.hash,
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

  @override
  void initState() {
    super.initState();
    _loadTextContent();
    _scrollController.addListener(_updateScrollProgress);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollProgress);
    _scrollController.dispose();
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
        );

        if (cachedContent != null) {
          setState(() {
            _content = cachedContent;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('翻译失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('下载功能开发中...'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
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
              child: SelectableText(
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
