import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/work.dart';
import '../providers/auth_provider.dart';
import '../providers/my_reviews_provider.dart';
import '../services/storage_service.dart';
import '../widgets/file_explorer_widget.dart';
import '../widgets/file_selection_dialog.dart';
import '../widgets/global_audio_player_wrapper.dart';
import '../widgets/tag_chip.dart';
import '../widgets/va_chip.dart';
import '../widgets/responsive_dialog.dart';

class WorkDetailScreen extends ConsumerStatefulWidget {
  final Work work;

  const WorkDetailScreen({
    super.key,
    required this.work,
  });

  @override
  ConsumerState<WorkDetailScreen> createState() => _WorkDetailScreenState();
}

class _WorkDetailScreenState extends ConsumerState<WorkDetailScreen> {
  Work? _detailedWork;
  String? _errorMessage;
  bool _showHDImage = false; // 控制是否显示高清图片
  ImageProvider? _hdImageProvider; // 预加载的高清图片
  String? _currentProgress; // 当前收藏状态
  bool _isUpdatingProgress = false; // 是否正在更新状态
  bool _isOpeningFileSelection = false; // iOS上防止快速重复点击造成对话框立即关闭
  bool _isOpeningProgressDialog = false; // 防止标记状态对话框重复快速打开

  @override
  void initState() {
    super.initState();
    // 初始化收藏状态（从传入的work中获取）
    _currentProgress = widget.work.progress;
    _loadWorkDetail();
    // Hero 动画结束后开始预加载高清图
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        _preloadHDImage();
      }
    });
  }

  // 预加载高清图片，完全加载后再切换
  Future<void> _preloadHDImage() async {
    final authState = ref.read(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';

    if (host.isEmpty) return;

    final imageUrl = widget.work.getCoverImageUrl(host, token: token);
    final imageProvider = NetworkImage(imageUrl);

    try {
      // 预加载图片到内存
      await precacheImage(imageProvider, context);
      // 图片完全加载后才切换显示
      if (mounted) {
        setState(() {
          _hdImageProvider = imageProvider;
          _showHDImage = true;
        });
      }
    } catch (e) {
      // 预加载失败，保持使用缓存图片
      debugPrint('HD image preload failed: $e');
    }
  }

  // 复制文本到剪贴板并显示提示
  Future<void> _copyToClipboard(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已复制$label：$text'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // 显示文件选择对话框
  Future<void> _showFileSelectionDialog() async {
    // 防抖: 避免 iOS 上快速双击导致同一路由被重复创建又立即被关闭
    if (_isOpeningFileSelection) return;
    _isOpeningFileSelection = true;

    final preparedWorkFuture = _prepareWorkForFileSelection();

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return FutureBuilder<Work>(
            future: preparedWorkFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const ResponsiveAlertDialog(
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('正在加载文件列表...'),
                    ],
                  ),
                );
              }

              if (snapshot.hasError) {
                return ResponsiveAlertDialog(
                  title: const Text('加载失败'),
                  content: Text('加载文件列表失败: ${snapshot.error}'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('关闭'),
                    ),
                  ],
                );
              }

              final work = snapshot.data!;
              return FileSelectionDialog(work: work);
            },
          );
        },
      );
    } finally {
      _isOpeningFileSelection = false;
    }
  }

  Future<Work> _prepareWorkForFileSelection() async {
    final apiService = ref.read(kikoeruApiServiceProvider);
    final files = await apiService.getWorkTracks(widget.work.id);
    final audioFiles = _convertToAudioFiles(files);
    final baseWork = _detailedWork ?? widget.work;
    return _cloneWorkWithChildren(baseWork, audioFiles);
  }

  Work _cloneWorkWithChildren(Work baseWork, List<AudioFile> audioFiles) {
    return Work(
      id: baseWork.id,
      title: baseWork.title,
      circleId: baseWork.circleId,
      name: baseWork.name,
      vas: baseWork.vas,
      tags: baseWork.tags,
      age: baseWork.age,
      release: baseWork.release,
      dlCount: baseWork.dlCount,
      price: baseWork.price,
      reviewCount: baseWork.reviewCount,
      rateCount: baseWork.rateCount,
      rateAverage: baseWork.rateAverage,
      hasSubtitle: baseWork.hasSubtitle,
      duration: baseWork.duration,
      progress: baseWork.progress,
      images: baseWork.images,
      description: baseWork.description,
      children: audioFiles,
    );
  }

  // 将 API 返回的文件列表转换为 AudioFile 对象
  List<AudioFile> _convertToAudioFiles(List<dynamic> files) {
    final authState = ref.read(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';

    // 标准化 host URL
    String normalizedHost = host;
    if (host.isNotEmpty &&
        !host.startsWith('http://') &&
        !host.startsWith('https://')) {
      normalizedHost = 'https://$host';
    }

    return files.map((file) {
      final type = file['type'] as String?;
      final title = file['title'] as String? ?? file['name'] as String? ?? '';
      final hash = file['hash'] as String?;
      final size = file['size'] as int?;

      // 构建下载 URL
      String? downloadUrl;
      if (file['mediaStreamUrl'] != null &&
          file['mediaStreamUrl'].toString().isNotEmpty) {
        downloadUrl = file['mediaStreamUrl'];
      } else if (normalizedHost.isNotEmpty &&
          hash != null &&
          type != 'folder') {
        downloadUrl = '$normalizedHost/api/media/stream/$hash?token=$token';
      }

      List<AudioFile>? children;
      if (file['children'] != null && file['children'] is List) {
        children = _convertToAudioFiles(file['children'] as List<dynamic>);
      }

      // API 返回的 type 是 'audio' 而不是 'file'
      return AudioFile(
        title: title,
        hash: hash,
        type: type == 'folder' ? 'folder' : 'file', // 将 'audio' 等类型统一转为 'file'
        children: children,
        size: size,
        mediaDownloadUrl: downloadUrl,
      );
    }).toList();
  }

  Future<void> _loadWorkDetail() async {
    try {
      setState(() {
        _errorMessage = null;
      });

      final apiService = ref.read(kikoeruApiServiceProvider);
      final response = await apiService.getWork(widget.work.id);
      final detailedWork = Work.fromJson(response);

      if (mounted) {
        setState(() {
          _detailedWork = detailedWork;
          // 更新收藏状态（从详情API响应中获取最新状态）
          _currentProgress = detailedWork.progress;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '加载失败: $e';
        });
      }
    }
  }

  // 下拉刷新：强制从网络获取最新数据
  Future<void> _refreshWorkDetail() async {
    try {
      setState(() {
        _errorMessage = null;
      });

      final apiService = ref.read(kikoeruApiServiceProvider);

      // 先清除缓存，确保获取最新数据
      final prefs = await StorageService.getPrefs();
      await prefs.remove('work_detail_${widget.work.id}');
      await prefs.remove('work_detail_time_${widget.work.id}');

      // 从网络获取最新数据
      final response = await apiService.getWork(widget.work.id);
      final detailedWork = Work.fromJson(response);

      if (mounted) {
        setState(() {
          _detailedWork = detailedWork;
          _currentProgress = detailedWork.progress;
        });

        // 显示刷新成功提示
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('刷新成功'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '刷新失败: $e';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('刷新失败: $e'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 显示收藏状态选择对话框
  Future<void> _showProgressDialog() async {
    if (_isOpeningProgressDialog) return; // 防抖避免 iOS 双击导致立即关闭
    _isOpeningProgressDialog = true;
    final filters = [
      MyReviewFilter.marked,
      MyReviewFilter.listening,
      MyReviewFilter.listened,
      MyReviewFilter.replay,
      MyReviewFilter.postponed,
    ];

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    String? selectedValue;

    if (isLandscape) {
      // 横屏模式：使用对话框形式，3+3两列布局
      selectedValue = await showDialog<String>(
        context: context,
        barrierDismissible: !Platform.isIOS, // iOS 上防止点击外部区域意外关闭
        builder: (dialogContext) {
          return Dialog(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.6,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 标题栏
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '选择收藏状态',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          tooltip: '关闭',
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // 内容区域 - 3+3两列布局，支持滚动
                  Flexible(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 左列：前3个选项
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: filters.take(3).map((filter) {
                                  final isSelected =
                                      _currentProgress == filter.value;
                                  return RadioListTile<String>(
                                    title: Text(filter.label),
                                    value: filter.value!,
                                    groupValue: _currentProgress,
                                    onChanged: (value) {
                                      Navigator.of(dialogContext).pop(value);
                                    },
                                    selected: isSelected,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                  );
                                }).toList(),
                              ),
                            ),
                            const VerticalDivider(width: 1),
                            // 右列：后2个选项 + 移除按钮
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ...filters.skip(3).map((filter) {
                                    final isSelected =
                                        _currentProgress == filter.value;
                                    return RadioListTile<String>(
                                      title: Text(filter.label),
                                      value: filter.value!,
                                      groupValue: _currentProgress,
                                      onChanged: (value) {
                                        Navigator.of(dialogContext).pop(value);
                                      },
                                      selected: isSelected,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 8),
                                    );
                                  }),
                                  if (_currentProgress != null) ...[
                                    const Divider(height: 1),
                                    ListTile(
                                      leading: Icon(
                                        Icons.delete_outline,
                                        color:
                                            Theme.of(context).colorScheme.error,
                                      ),
                                      title: Text(
                                        '移除',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                      ),
                                      onTap: () {
                                        Navigator.of(dialogContext).pop('__REMOVE__');
                                      },
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 8),
                                    ),
                                  ],
                                ],
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
          );
        },
      );
    } else {
      // 竖屏模式：使用底部弹窗
      selectedValue = await showResponsiveBottomSheet<String>(
        context: context,
        isDismissible: !Platform.isIOS, // iOS 上防止点击外部区域或下拉意外关闭
        enableDrag: !Platform.isIOS, // iOS 上禁止下拉关闭
        builder: (context) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    '选择收藏状态',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                const Divider(),
                ...filters.map((filter) {
                  final isSelected = _currentProgress == filter.value;
                  return ListTile(
                    leading: Icon(
                      isSelected ? Icons.check_circle : Icons.circle_outlined,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(filter.label),
                    selected: isSelected,
                    onTap: () {
                      Navigator.pop(context, filter.value);
                    },
                  );
                }).toList(),
                const SizedBox(height: 8),
                if (_currentProgress != null)
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      '移除',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context, '__REMOVE__');
                    },
                  ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(context); // 取消，不返回任何值
                      },
                      child: const Text('取消'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    _isOpeningProgressDialog = false;

    // 等待对话框完全关闭后再执行状态更新，避免 iOS 上的闪退
    if (selectedValue != null) {
      if (selectedValue == '__REMOVE__') {
        await _updateProgress(null);
      } else {
        await _updateProgress(selectedValue);
      }
    }
  }

  // 更新收藏状态
  Future<void> _updateProgress(String? progress) async {
    if (_isUpdatingProgress) return;

    setState(() {
      _isUpdatingProgress = true;
    });

    try {
      final apiService = ref.read(kikoeruApiServiceProvider);

      if (progress != null) {
        await apiService.updateReviewProgress(
          widget.work.id,
          progress: progress,
        );

        setState(() {
          _currentProgress = progress;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已设置为：${_getProgressLabel(progress)}'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        // 删除收藏状态
        await apiService.deleteReview(widget.work.id);

        setState(() {
          _currentProgress = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已移除标记'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('更新失败: $e'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      setState(() {
        _isUpdatingProgress = false;
      });
    }
  }

  // 获取状态标签
  String _getProgressLabel(String? progress) {
    if (progress == null) return '标记';

    final filter = [
      MyReviewFilter.marked,
      MyReviewFilter.listening,
      MyReviewFilter.listened,
      MyReviewFilter.replay,
      MyReviewFilter.postponed,
    ].firstWhere(
      (f) => f.value == progress,
      orElse: () => MyReviewFilter.all,
    );

    return filter.label;
  }

  // 获取状态对应的图标
  IconData _getProgressIcon(String? progress) {
    if (progress == null) return Icons.bookmark_border;

    switch (progress) {
      case 'marked':
        return Icons.bookmark;
      case 'listening':
        return Icons.headphones;
      case 'listened':
        return Icons.check_circle;
      case 'replay':
        return Icons.replay;
      case 'postponed':
        return Icons.schedule;
      default:
        return Icons.bookmark;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlobalAudioPlayerWrapper(
      child: Scaffold(
        appBar: AppBar(
          // RJ号作为标题,支持长按复制
          title: GestureDetector(
            onLongPress: () => _copyToClipboard('RJ${widget.work.id}', 'RJ号'),
            child: Text(
              'RJ${widget.work.id}',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            // 下载按钮
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: _showFileSelectionDialog,
              tooltip: '下载',
            ),
            // 收藏状态按钮 - 带图标和文字
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _isUpdatingProgress
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    )
                  : TextButton(
                      onPressed: _showProgressDialog,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _getProgressLabel(_currentProgress),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: _currentProgress != null
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _getProgressIcon(_currentProgress),
                            size: 22,
                            color: _currentProgress != null
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final authState = ref.watch(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    // 使用已有的work信息（来自列表），详细信息加载后再更新
    final work = _detailedWork ?? widget.work;

    // 封面图片组件
    final coverWidget = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Hero(
        tag: 'work_cover_${widget.work.id}',
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: isLandscape ? null : double.infinity,
            constraints: BoxConstraints(
              maxHeight:
                  isLandscape ? MediaQuery.of(context).size.height * 0.8 : 500,
              maxWidth: isLandscape
                  ? MediaQuery.of(context).size.width * 0.45
                  : double.infinity,
            ),
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                // 底层：缓存图片，始终显示
                CachedNetworkImage(
                  imageUrl: work.getCoverImageUrl(host, token: token),
                  cacheKey: 'work_cover_${widget.work.id}',
                  fit: BoxFit.contain,
                  placeholder: (context, url) => Container(
                    height: 300,
                    color: Colors.grey[300],
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    height: 300,
                    color: Colors.grey[300],
                    child: const Icon(
                      Icons.image_not_supported,
                      size: 64,
                      color: Colors.grey,
                    ),
                  ),
                ),
                // 顶层：高清图，加载完成后覆盖
                if (_showHDImage && _hdImageProvider != null)
                  Image(
                    image: _hdImageProvider!,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const SizedBox.shrink(); // 出错时不显示，保持底层缓存图
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    // 信息内容组件
    final infoWidget = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题（可长按复制）+ 内联字幕图标（紧跟标题最后一个字，不换行）
          GestureDetector(
            onLongPress: () => _copyToClipboard(work.title, '标题'),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: work.title),
                  if (work.hasSubtitle == true)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'CC',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
              textAlign: TextAlign.start,
              softWrap: true,
            ),
          ),
          const SizedBox(height: 8),

          // 显示加载状态或错误信息
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      size: 16, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadWorkDetail,
                    child: const Text('重试', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),

          // 评分信息 价格和销售信息
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // 评分信息 - 总是显示
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    (work.rateAverage != null &&
                            work.rateCount != null &&
                            work.rateCount! > 0)
                        ? work.rateAverage!.toStringAsFixed(1)
                        : '-',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '(${work.rateCount ?? 0})',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),

              // 时长信息
              if (work.duration != null && work.duration! > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.access_time, color: Colors.blue, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      _formatDuration(work.duration!),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.blue[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),

              // 价格信息
              if (work.price != null)
                Text(
                  '${work.price} 日元',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.red[700],
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                ),

              // 销售数量信息
              if (work.dlCount != null && work.dlCount! > 0)
                Text(
                  '售出：${_formatNumber(work.dlCount!)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // 社团和声优信息
          if ((work.name != null && work.name!.isNotEmpty) ||
              (work.vas != null && work.vas!.isNotEmpty)) ...[
            Text(
              '社团 | 声优',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
            ),
            const SizedBox(height: 8),

            // 社团和声优放在同一行
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                // 社团名称标签
                if (work.name != null && work.name!.isNotEmpty)
                  GestureDetector(
                    onLongPress: () => _copyToClipboard(work.name!, '社团'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        work.name!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),

                // 声优列表
                if (work.vas != null && work.vas!.isNotEmpty)
                  ...work.vas!.map((va) {
                    return VaChip(
                      va: va,
                      fontSize: 12,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      borderRadius: 6,
                      fontWeight: FontWeight.w500,
                      onLongPress: () => _copyToClipboard(va.name, '声优'),
                    );
                  }).toList(),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // 标签信息
          if (work.tags != null && work.tags!.isNotEmpty) ...[
            Text(
              '标签',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: work.tags!
                  .map((tag) => TagChip(
                        tag: tag,
                        fontSize: 12,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        borderRadius: 6,
                        fontWeight: FontWeight.w500,
                        onLongPress: () => _copyToClipboard(tag.name, '标签'),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],

          // 发布日期
          if (work.release != null) ...[
            Text(
              '发布日期',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              work.release!.split('T')[0],
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                  ),
            ),
            const SizedBox(height: 24),
          ],

          // 播放按钮 - 替换为文件浏览器
          Text(
            '资源文件',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
          ),
          const SizedBox(height: 8),

          // 文件浏览器组件 - 移除固定高度，让它自由展开
          FileExplorerWidget(work: work),
        ],
      ),
    );

    // 根据屏幕方向返回不同布局
    if (isLandscape) {
      // 横屏布局：左右分栏 - 左侧封面固定，右侧信息可滚动
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：封面（固定不滚动）
          Expanded(
            flex: 2,
            child: Center(
              child: coverWidget,
            ),
          ),
          // 右侧：信息（可滚动，带下拉刷新）
          Expanded(
            flex: 3,
            child: RefreshIndicator(
              onRefresh: _refreshWorkDetail,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(0),
                physics: const AlwaysScrollableScrollPhysics(),
                child: infoWidget,
              ),
            ),
          ),
        ],
      );
    } else {
      // 竖屏布局：上下排列
      return RefreshIndicator(
        onRefresh: _refreshWorkDetail,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(0),
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              coverWidget,
              infoWidget,
            ],
          ),
        ),
      );
    }
  }

  String _formatNumber(int number) {
    if (number >= 10000) {
      return '${(number / 10000).toStringAsFixed(1)}万';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}k';
    } else {
      return number.toString();
    }
  }

  // 格式化时长(秒 -> 时:分:秒 或 分:秒)
  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${secs.toString().padLeft(2, '0')}';
    }
  }
}
