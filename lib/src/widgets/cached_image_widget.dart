import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../services/cache_service.dart';

/// 支持缓存的网络图片组件
class CachedImageWidget extends StatefulWidget {
  final String imageUrl;
  final String hash;
  final int? workId;
  final BoxFit fit;

  const CachedImageWidget({
    super.key,
    required this.imageUrl,
    required this.hash,
    this.workId,
    this.fit = BoxFit.contain,
  });

  @override
  State<CachedImageWidget> createState() => _CachedImageWidgetState();
}

class _CachedImageWidgetState extends State<CachedImageWidget> {
  String? _cachedFilePath;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    // 优先检查是否是本地文件（file:// 协议）
    if (widget.imageUrl.startsWith('file://')) {
      final localPath = widget.imageUrl.substring(7); // 移除 'file://' 前缀
      final localFile = File(localPath);

      if (await localFile.exists()) {
        setState(() {
          _cachedFilePath = localPath;
          _isLoading = false;
        });
        return;
      } else {
        debugPrint('[Cache] 本地图片文件不存在: $localPath');
        setState(() => _isLoading = false);
        return;
      }
    }

    if (widget.workId == null || widget.hash.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final cachedPath = await CacheService.getCachedFileResource(
        workId: widget.workId!,
        hash: widget.hash,
        fileType: 'image',
      );

      if (cachedPath != null && mounted) {
        setState(() {
          _cachedFilePath = cachedPath;
          _isLoading = false;
        });
        return;
      }

      final dio = Dio();
      final newCachedPath = await CacheService.cacheFileResource(
        workId: widget.workId!,
        hash: widget.hash,
        fileType: 'image',
        url: widget.imageUrl,
        dio: dio,
      );

      if (newCachedPath != null && mounted) {
        setState(() {
          _cachedFilePath = newCachedPath;
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('[Cache] 图片缓存加载失败: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_cachedFilePath != null) {
      return Image.file(
        File(_cachedFilePath!),
        fit: widget.fit,
        errorBuilder: (context, error, stackTrace) {
          return Image.network(
            widget.imageUrl,
            fit: widget.fit,
            errorBuilder: (context, error, stackTrace) =>
                _buildErrorWidget(error.toString()),
          );
        },
      );
    }

    return Image.network(
      widget.imageUrl,
      fit: widget.fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: CircularProgressIndicator(
            value: loadingProgress.expectedTotalBytes != null
                ? loadingProgress.cumulativeBytesLoaded /
                    loadingProgress.expectedTotalBytes!
                : null,
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) =>
          _buildErrorWidget(error.toString()),
    );
  }

  Widget _buildErrorWidget(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            '加载图片失败\n$error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
        ],
      ),
    );
  }
}
