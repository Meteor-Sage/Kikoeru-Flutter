import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'cached_image_widget.dart';

/// 图片画廊屏幕，支持查看、缩放、保存图片
class ImageGalleryScreen extends StatefulWidget {
  final List<Map<String, String>> images;
  final int initialIndex;
  final int? workId;

  const ImageGalleryScreen({
    super.key,
    required this.images,
    this.initialIndex = 0,
    this.workId,
  });

  @override
  State<ImageGalleryScreen> createState() => _ImageGalleryScreenState();
}

class _ImageGalleryScreenState extends State<ImageGalleryScreen> {
  late PageController _pageController;
  late int _currentIndex;
  final Map<int, TransformationController> _transformControllers = {};
  bool _isScaled = false;
  int _pointerCount = 0;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (var controller in _transformControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TransformationController _getTransformController(int index) {
    if (!_transformControllers.containsKey(index)) {
      _transformControllers[index] = TransformationController();
    }
    return _transformControllers[index]!;
  }

  void _handleDoubleTap(int index) {
    final controller = _getTransformController(index);
    final currentScale = controller.value.getMaxScaleOnAxis();

    if (currentScale > 1.0) {
      controller.value = Matrix4.identity();
      setState(() => _isScaled = false);
    } else {
      const newScale = 2.0;
      controller.value = Matrix4.identity()..scale(newScale);
      setState(() => _isScaled = true);
    }
  }

  void _handleTapNavigation(TapDownDetails details) {
    if (_isScaled || _pointerCount > 0) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final tapPosition = details.globalPosition.dx;

    if (tapPosition < screenWidth / 3) {
      if (_currentIndex > 0) {
        _pageController.previousPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    } else if (tapPosition > screenWidth * 2 / 3) {
      if (_currentIndex < widget.images.length - 1) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  Future<void> _saveImage() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      final currentImage = widget.images[_currentIndex];
      final imageUrl = currentImage['url'] ?? '';
      final imageName = currentImage['title'] ?? 'image_${_currentIndex + 1}';

      List<int> imageBytes;

      // 检查是否是本地文件
      if (imageUrl.startsWith('file://')) {
        final localPath = imageUrl.substring(7); // 移除 'file://' 前缀
        final localFile = File(localPath);
        imageBytes = await localFile.readAsBytes();
      } else {
        // 网络图片，使用 Dio 下载
        final response = await Dio().get(
          imageUrl,
          options: Options(responseType: ResponseType.bytes),
        );
        imageBytes = response.data as List<int>;
      }

      if (Platform.isAndroid) {
        await _saveToGallery(imageBytes, imageName);
      } else {
        await _saveToFile(imageBytes, imageName);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _saveToGallery(List<int> imageBytes, String imageName) async {
    PermissionStatus status = await Permission.photos.request();

    if (status.isPermanentlyDenied || status == PermissionStatus.restricted) {
      status = await Permission.storage.request();
    }

    if (!status.isGranted) {
      if (mounted) {
        if (status.isPermanentlyDenied) {
          final shouldOpenSettings = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('需要存储权限'),
              content: const Text('保存图片需要访问相册的权限。请在设置中授予权限。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('去设置'),
                ),
              ],
            ),
          );

          if (shouldOpenSettings == true) {
            await openAppSettings();
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('需要存储权限才能保存图片'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
      return;
    }

    final result = await SaverGallery.saveImage(
      Uint8List.fromList(imageBytes),
      fileName: imageName,
      skipIfExists: false,
      androidRelativePath: "Pictures/KikoFlu",
    );

    if (mounted) {
      if (result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('图片已保存到相册'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: ${result.errorMessage ?? "未知错误"}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveToFile(List<int> imageBytes, String imageName) async {
    String fileName = imageName;
    if (!fileName.toLowerCase().endsWith('.jpg') &&
        !fileName.toLowerCase().endsWith('.jpeg') &&
        !fileName.toLowerCase().endsWith('.png') &&
        !fileName.toLowerCase().endsWith('.gif')) {
      fileName += '.jpg';
    }

    if (Platform.isIOS) {
      try {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/$fileName');
        await tempFile.writeAsBytes(imageBytes);

        final outputFile = await FilePicker.platform.saveFile(
          dialogTitle: '保存图片',
          fileName: fileName,
          type: FileType.image,
          bytes: Uint8List.fromList(imageBytes),
        );

        if (outputFile != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('图片已保存'),
              backgroundColor: Colors.green,
            ),
          );
        }

        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('保存失败: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      final outputFile = await FilePicker.platform.saveFile(
        dialogTitle: '保存图片',
        fileName: fileName,
        type: FileType.image,
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsBytes(imageBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('图片已保存到: $outputFile'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final currentImage = widget.images[_currentIndex];
    final title = currentImage['title'] ?? '';
    final pageLabel = '${_currentIndex + 1}/${widget.images.length}';

    final imageArea = _buildImagePageView(isLandscape);

    if (isLandscape) {
      return Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          scrolledUnderElevation: 0,
          backgroundColor: Colors.black.withOpacity(0.4),
          elevation: 0,
          foregroundColor: Colors.white,
          title: Text(pageLabel),
          actions: [
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.download),
                onPressed: _saveImage,
                tooltip: '保存图片',
              ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: imageArea),
              if (title.isNotEmpty)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: _buildTitleBadge(title),
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.black,
        elevation: 0,
        foregroundColor: Colors.white,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(pageLabel, style: const TextStyle(fontSize: 16)),
            if (title.isNotEmpty)
              Text(
                title,
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: _saveImage,
              tooltip: '保存图片',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: imageArea),
                if (title.isNotEmpty)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 24,
                    child: _buildTitleBadge(title),
                  ),
              ],
            ),
          ),
          _buildThumbnailStrip(),
        ],
      ),
    );
  }

  Widget _buildImagePageView(bool isLandscape) {
    return Listener(
      onPointerDown: (_) => _updatePointerCount(increment: true),
      onPointerUp: (_) => _updatePointerCount(increment: false),
      onPointerCancel: (_) => _resetPointerCount(),
      child: PageView.builder(
        controller: _pageController,
        itemCount: widget.images.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
            _isScaled = false;
            _pointerCount = 0;
          });
          _resetAllTransformations();
        },
        physics: _isScaled || _pointerCount > 1
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        itemBuilder: (context, index) {
          final image = widget.images[index];
          final controller = _getTransformController(index);

          return GestureDetector(
            onTapDown: _handleTapNavigation,
            onDoubleTap: () => _handleDoubleTap(index),
            child: InteractiveViewer(
              clipBehavior: Clip.none,
              transformationController: controller,
              minScale: 1.0,
              maxScale: 4.0,
              onInteractionEnd: (_) {
                final maxScale = controller.value.getMaxScaleOnAxis();
                setState(() => _isScaled = maxScale > 1.01);
              },
              child: Container(
                color: Colors.black,
                alignment: Alignment.center,
                child: CachedImageWidget(
                  imageUrl: image['url'] ?? '',
                  hash: image['hash'] ?? '',
                  workId: widget.workId,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildThumbnailStrip() {
    return Container(
      height: 140,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.black,
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            offset: Offset(0, -2),
            blurRadius: 8,
          ),
        ],
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: widget.images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final isSelected = index == _currentIndex;

          return GestureDetector(
            onTap: () => _jumpToImage(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: 90,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSelected ? Colors.white : Colors.transparent,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: CachedImageWidget(
                  imageUrl: widget.images[index]['url'] ?? '',
                  hash: widget.images[index]['hash'] ?? '',
                  workId: widget.workId,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTitleBadge(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  void _jumpToImage(int index) {
    if (index == _currentIndex) return;
    _resetAllTransformations();
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  void _resetAllTransformations() {
    for (final controller in _transformControllers.values) {
      controller.value = Matrix4.identity();
    }
  }

  void _updatePointerCount({required bool increment}) {
    setState(() {
      if (increment) {
        _pointerCount += 1;
      } else {
        _pointerCount = _pointerCount > 0 ? _pointerCount - 1 : 0;
      }
    });
  }

  void _resetPointerCount() {
    if (_pointerCount == 0) return;
    setState(() => _pointerCount = 0);
  }
}
