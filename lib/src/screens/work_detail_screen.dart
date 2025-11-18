import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/work.dart';
import '../providers/auth_provider.dart';
import '../widgets/scrollable_appbar.dart';
import '../services/storage_service.dart';
import '../widgets/file_explorer_widget.dart';
import '../widgets/file_selection_dialog.dart';
import '../widgets/global_audio_player_wrapper.dart';
import '../widgets/tag_chip.dart';
import '../widgets/va_chip.dart';
import '../widgets/circle_chip.dart';
import '../widgets/responsive_dialog.dart';
import '../widgets/work_bookmark_manager.dart';
import '../widgets/review_progress_dialog.dart';
import '../widgets/rating_detail_popup.dart';
import '../services/translation_service.dart';
import '../widgets/download_fab.dart';

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
  int? _currentRating; // 当前评分
  bool _isUpdatingProgress = false; // 是否正在更新状态
  bool _isOpeningFileSelection = false; // iOS上防止快速重复点击造成对话框立即关闭
  bool _isOpeningProgressDialog = false; // 防止标记状态对话框重复快速打开

  // 翻译相关状态
  String? _translatedTitle; // 翻译后的标题
  bool _showTranslation = false; // 是否显示翻译
  bool _isTranslating = false; // 是否正在翻译

  @override
  void initState() {
    super.initState();
    // 初始化收藏状态（从传入的work中获取）
    _currentProgress = widget.work.progress;
    _currentRating = widget.work.userRating;
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

  // 翻译标题
  Future<void> _translateTitle() async {
    if (_isTranslating) return;

    final work = _detailedWork ?? widget.work;

    // 如果已有翻译，直接切换显示
    if (_translatedTitle != null) {
      setState(() {
        _showTranslation = !_showTranslation;
      });
      return;
    }

    setState(() {
      _isTranslating = true;
    });

    try {
      final translationService = TranslationService();
      final translated =
          await translationService.translate(work.title, sourceLang: 'ja');

      if (mounted) {
        setState(() {
          _translatedTitle = translated;
          _showTranslation = true;
          _isTranslating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTranslating = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('翻译失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
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

  // 显示标签投票信息
  void _showTagInfo(Tag tag) {
    showDialog(
      context: context,
      builder: (context) => _TagVoteDialog(
        tag: tag,
        workId: widget.work.id,
        onVoteChanged: (updatedTag) {
          // 投票成功后更新本地状态
          if (mounted) {
            setState(() {
              // 更新 _detailedWork 中的 tag
              if (_detailedWork != null && _detailedWork!.tags != null) {
                final tagIndex = _detailedWork!.tags!
                    .indexWhere((t) => t.id == updatedTag.id);
                if (tagIndex != -1) {
                  final updatedTags = List<Tag>.from(_detailedWork!.tags!);
                  updatedTags[tagIndex] = updatedTag;
                  _detailedWork = Work(
                    id: _detailedWork!.id,
                    title: _detailedWork!.title,
                    circleId: _detailedWork!.circleId,
                    name: _detailedWork!.name,
                    vas: _detailedWork!.vas,
                    tags: updatedTags,
                    age: _detailedWork!.age,
                    release: _detailedWork!.release,
                    dlCount: _detailedWork!.dlCount,
                    price: _detailedWork!.price,
                    reviewCount: _detailedWork!.reviewCount,
                    rateCount: _detailedWork!.rateCount,
                    rateAverage: _detailedWork!.rateAverage,
                    hasSubtitle: _detailedWork!.hasSubtitle,
                    duration: _detailedWork!.duration,
                    progress: _detailedWork!.progress,
                    userRating: _detailedWork!.userRating,
                    rateCountDetail: _detailedWork!.rateCountDetail,
                    images: _detailedWork!.images,
                    description: _detailedWork!.description,
                    children: _detailedWork!.children,
                    sourceUrl: _detailedWork!.sourceUrl,
                    otherLanguageEditions: _detailedWork!.otherLanguageEditions,
                  );
                }
              }
            });
          }
        },
        onCopyTag: () => _copyToClipboard(tag.name, '标签'),
      ),
    );
  }

  // 显示添加标签对话框
  void _showAddTagDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddTagDialog(
        workId: widget.work.id,
        existingTags: _detailedWork?.tags ?? widget.work.tags ?? [],
        onTagsAdded: () {
          // 添加成功后刷新作品详情
          _loadWorkDetail();
        },
      ),
    );
  }

  // 在外部浏览器打开原始链接
  Future<void> _openSourceUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      // 直接尝试在外部浏览器打开，不依赖 canLaunchUrl 检查
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && mounted) {
        // 如果外部应用模式失败，尝试平台默认方式
        final fallbackLaunched = await launchUrl(
          uri,
          mode: LaunchMode.platformDefault,
        );

        if (!fallbackLaunched && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('无法打开链接'),
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
            content: Text('打开链接失败: $e'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
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
      otherLanguageEditions: baseWork.otherLanguageEditions,
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
          // 更新收藏状态（从API响应中获取最新状态）
          _currentProgress = detailedWork.progress;
          _currentRating = detailedWork.userRating;
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
          _currentRating = detailedWork.userRating;
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

    final manager = WorkBookmarkManager(ref: ref, context: context);

    await manager.showMarkDialog(
      workId: widget.work.id,
      currentProgress: _currentProgress,
      currentRating: _currentRating,
      onChanged: (newProgress, newRating) {
        // 更新本地状态
        if (mounted) {
          setState(() {
            _currentProgress = newProgress;
            _currentRating = newRating;
            _isUpdatingProgress = false;
          });
        }
      },
    );

    _isOpeningProgressDialog = false;
  }

  // 显示评分详情弹窗
  Future<void> _showRatingDetailDialog(Work work) async {
    if (work.rateCountDetail == null || work.rateCountDetail!.isEmpty) return;
    if (work.rateAverage == null || work.rateCount == null) return;

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: RatingDetailPopup(
          ratingDetails: work.rateCountDetail!,
          averageRating: work.rateAverage!,
          totalCount: work.rateCount!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 根据主题亮度设置状态栏图标颜色
    final brightness = Theme.of(context).brightness;
    final systemOverlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: brightness == Brightness.light
          ? Brightness.dark // 浅色模式用深色图标
          : Brightness.light, // 深色模式用浅色图标
      systemNavigationBarColor: Colors.transparent,
    );

    return GlobalAudioPlayerWrapper(
      child: Scaffold(
        floatingActionButton: const DownloadFab(),
        appBar: ScrollableAppBar(
          systemOverlayStyle: systemOverlayStyle,
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
                            ReviewProgressDialog.getProgressLabel(
                                _currentProgress),
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
                            ReviewProgressDialog.getProgressIcon(
                                _currentProgress),
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
                // 字幕标签 - 浮动在右下角
                if (work.hasSubtitle == true)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        '字幕',
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
            onLongPress: () => _copyToClipboard(
              _showTranslation && _translatedTitle != null
                  ? _translatedTitle!
                  : work.title,
              '标题',
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: _showTranslation && _translatedTitle != null
                        ? _translatedTitle
                        : work.title,
                  ),
                  if (work.sourceUrl != null)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => _openSourceUrl(work.sourceUrl!),
                            child: Icon(
                              Icons.open_in_new,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // 翻译按钮
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: MouseRegion(
                        cursor: _isTranslating
                            ? SystemMouseCursors.basic
                            : SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: _isTranslating ? null : _translateTitle,
                          child: _isTranslating
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
                                  size: 18,
                                  color: _showTranslation
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withOpacity(0.6),
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
              // 评分信息 - 总是显示，支持悬浮显示详情
              MouseRegion(
                cursor: work.rateCountDetail != null &&
                        work.rateCountDetail!.isNotEmpty
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: GestureDetector(
                  onTap: () {
                    if (work.rateCountDetail != null &&
                        work.rateCountDetail!.isNotEmpty) {
                      _showRatingDetailDialog(work);
                    }
                  },
                  child: Tooltip(
                    message: work.rateCountDetail != null &&
                            work.rateCountDetail!.isNotEmpty
                        ? '点击查看评分详情'
                        : '',
                    preferBelow: false,
                    child: Row(
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
                        // 括号内包含数字和感叹号图标
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '(',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              '${work.rateCount ?? 0}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                            // 如果有详情数据，显示信息图标
                            if (work.rateCountDetail != null &&
                                work.rateCountDetail!.isNotEmpty)
                              Icon(
                                Icons.info_outline,
                                size: 14,
                                color: Colors.grey[600],
                              ),
                            Text(
                              ')',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 我的评分 - 仅当有评分时显示
              if (_currentRating != null)
                InkWell(
                  onTap: _showProgressDialog,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.person,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.star,
                          color: Colors.amber,
                          size: 14,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '$_currentRating',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                if (work.name != null &&
                    work.name!.isNotEmpty &&
                    work.circleId != null)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: CircleChip(
                      circleId: work.circleId!,
                      circleName: work.name!,
                      fontSize: 12,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      borderRadius: 6,
                      fontWeight: FontWeight.w500,
                      onLongPress: () => _copyToClipboard(work.name!, '社团'),
                    ),
                  ),

                // 声优列表
                if (work.vas != null && work.vas!.isNotEmpty)
                  ...work.vas!.map((va) {
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: VaChip(
                        va: va,
                        fontSize: 12,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        borderRadius: 6,
                        fontWeight: FontWeight.w500,
                        onLongPress: () => _copyToClipboard(va.name, '声优'),
                      ),
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
              children: [
                ...work.tags!
                    .map((tag) => MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onSecondaryTapDown: (details) {
                              // 桌面端右键支持
                              _showTagInfo(tag);
                            },
                            child: TagChip(
                              tag: tag,
                              fontSize: 12,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              borderRadius: 6,
                              fontWeight: FontWeight.w500,
                              onLongPress: () => _showTagInfo(tag),
                            ),
                          ),
                        ))
                    .toList(),
                // 添加标签按钮
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _showAddTagDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withOpacity(0.3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.add,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ] else ...[
            // 如果没有标签，也显示添加按钮
            GestureDetector(
              onTap: _showAddTagDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withOpacity(0.3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '添加标签',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
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
            const SizedBox(height: 16),
          ],

          // 其他语言版本
          if (work.otherLanguageEditions != null &&
              work.otherLanguageEditions!.isNotEmpty) ...[
            Text(
              '其他版本',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: work.otherLanguageEditions!.map((edition) {
                return InkWell(
                  onTap: () {
                    // 导航到其他语言版本的作品详情页
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => WorkDetailScreen(
                          work: Work(
                            id: edition.id,
                            title: edition.title,
                          ),
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .secondaryContainer
                          .withOpacity(0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.translate,
                          size: 14,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '「${edition.lang}」',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],

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

// 标签投票对话框组件
class _TagVoteDialog extends ConsumerStatefulWidget {
  final Tag tag;
  final int workId;
  final Function(Tag) onVoteChanged;
  final VoidCallback onCopyTag;

  const _TagVoteDialog({
    required this.tag,
    required this.workId,
    required this.onVoteChanged,
    required this.onCopyTag,
  });

  @override
  ConsumerState<_TagVoteDialog> createState() => _TagVoteDialogState();
}

class _TagVoteDialogState extends ConsumerState<_TagVoteDialog> {
  late Tag _currentTag;
  bool _isVoting = false;

  @override
  void initState() {
    super.initState();
    _currentTag = widget.tag;
  }

  Future<void> _handleVote(int targetStatus) async {
    if (_isVoting) return;

    setState(() {
      _isVoting = true;
    });

    try {
      // 如果点击已投的票，则取消投票
      final newStatus = _currentTag.myVote == targetStatus ? 0 : targetStatus;

      final apiService = ref.read(kikoeruApiServiceProvider);
      await apiService.voteWorkTag(
        workId: widget.workId,
        tagId: _currentTag.id,
        status: newStatus,
      );

      // 投票成功，更新本地状态
      if (mounted) {
        setState(() {
          final oldUpvote = _currentTag.upvote ?? 0;
          final oldDownvote = _currentTag.downvote ?? 0;
          int newUpvote = oldUpvote;
          int newDownvote = oldDownvote;

          // 先移除旧投票的影响
          if (_currentTag.myVote == 1) {
            newUpvote = oldUpvote - 1;
          } else if (_currentTag.myVote == 2) {
            newDownvote = oldDownvote - 1;
          }

          // 再添加新投票的影响
          if (newStatus == 1) {
            newUpvote = newUpvote + 1;
          } else if (newStatus == 2) {
            newDownvote = newDownvote + 1;
          }

          _currentTag = Tag(
            id: _currentTag.id,
            name: _currentTag.name,
            upvote: newUpvote,
            downvote: newDownvote,
            myVote: newStatus == 0 ? null : newStatus,
          );

          _isVoting = false;
        });

        // 通知父组件更新
        widget.onVoteChanged(_currentTag);

        // 显示提示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus == 0
                  ? '已取消投票'
                  : newStatus == 1
                      ? '已投支持票'
                      : '已投反对票',
            ),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVoting = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('投票失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveAlertDialog(
      title: Text(
        _currentTag.name,
        style: const TextStyle(fontSize: 16),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 投票支持按钮
          InkWell(
            onTap: _isVoting ? null : () => _handleVote(1),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _currentTag.myVote == 1
                    ? Colors.green.withOpacity(0.1)
                    : Colors.grey.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _currentTag.myVote == 1
                      ? Colors.green
                      : Colors.grey.withOpacity(0.3),
                  width: _currentTag.myVote == 1 ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.thumb_up,
                    color: _currentTag.myVote == 1 ? Colors.green : Colors.grey,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '支持：${_currentTag.upvote ?? 0}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: _currentTag.myVote == 1
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: _currentTag.myVote == 1 ? Colors.green : null,
                      ),
                    ),
                  ),
                  if (_currentTag.myVote == 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '已投票',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (_isVoting && _currentTag.myVote != 1)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 投票反对按钮
          InkWell(
            onTap: _isVoting ? null : () => _handleVote(2),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _currentTag.myVote == 2
                    ? Colors.red.withOpacity(0.1)
                    : Colors.grey.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _currentTag.myVote == 2
                      ? Colors.red
                      : Colors.grey.withOpacity(0.3),
                  width: _currentTag.myVote == 2 ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.thumb_down,
                    color: _currentTag.myVote == 2 ? Colors.red : Colors.grey,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '反对：${_currentTag.downvote ?? 0}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: _currentTag.myVote == 2
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: _currentTag.myVote == 2 ? Colors.red : null,
                      ),
                    ),
                  ),
                  if (_currentTag.myVote == 2)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '已投票',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (_isVoting && _currentTag.myVote != 2)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.pop(context);
            widget.onCopyTag();
          },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('复制标签'),
        ),
      ],
    );
  }
}

// 添加标签对话框组件
class _AddTagDialog extends ConsumerStatefulWidget {
  final int workId;
  final List<Tag> existingTags;
  final VoidCallback onTagsAdded;

  const _AddTagDialog({
    required this.workId,
    required this.existingTags,
    required this.onTagsAdded,
  });

  @override
  ConsumerState<_AddTagDialog> createState() => _AddTagDialogState();
}

class _AddTagDialogState extends ConsumerState<_AddTagDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allTags = [];
  List<Map<String, dynamic>> _filteredTags = [];
  final Set<int> _selectedTagIds = {};
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadAllTags();
    _searchController.addListener(_filterTags);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllTags() async {
    try {
      final apiService = ref.read(kikoeruApiServiceProvider);
      final data = await apiService.getAllTags();

      if (mounted) {
        setState(() {
          _allTags = List<Map<String, dynamic>>.from(data);
          // 按 count 字段从大到小排序
          _allTags.sort((a, b) => (b['count'] ?? 0).compareTo(a['count'] ?? 0));
          _filteredTags = _allTags;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载标签失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _filterTags() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredTags = _allTags;
      } else {
        _filteredTags = _allTags
            .where(
                (tag) => tag['name'].toString().toLowerCase().contains(query))
            .toList();
      }
    });
  }

  Future<void> _submitTags() async {
    if (_selectedTagIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请至少选择一个标签'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final apiService = ref.read(kikoeruApiServiceProvider);
      await apiService.attachTagsToWork(
        workId: widget.workId,
        tagIds: _selectedTagIds.toList(),
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onTagsAdded();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('标签提交成功，等待服务器处理'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });

        String errorMessage = '添加标签失败: $e';

        // 检查是否需要绑定邮箱
        if (e.toString().contains('Must bind email first') ||
            e.toString().contains('vote.mustBindEmailFirst')) {
          errorMessage = '请先前往 www.asmr.one 绑定邮箱';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 获取已存在的标签ID集合
    final existingTagIds = widget.existingTags.map((tag) => tag.id).toSet();

    return ResponsiveAlertDialog(
      title: const Text('添加标签'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 搜索框
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索标签...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 已选择的标签
            if (_selectedTagIds.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '已选择 ${_selectedTagIds.length} 个标签:',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: _selectedTagIds.map((tagId) {
                  final tag = _allTags.firstWhere((t) => t['id'] == tagId);
                  return Chip(
                    label: Text(
                      tag['name'],
                      style: const TextStyle(fontSize: 11),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      setState(() {
                        _selectedTagIds.remove(tagId);
                      });
                    },
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // 标签列表
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                child: _filteredTags.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('没有找到匹配的标签'),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _filteredTags.length,
                        itemBuilder: (context, index) {
                          final tag = _filteredTags[index];
                          final tagId = tag['id'] as int;
                          final tagName = tag['name'] as String;
                          final count = tag['count'] ?? 0;
                          final isExisting = existingTagIds.contains(tagId);
                          final isSelected = _selectedTagIds.contains(tagId);

                          return ListTile(
                            dense: true,
                            enabled: !isExisting,
                            title: Text(
                              tagName,
                              style: TextStyle(
                                fontSize: 13,
                                color: isExisting ? Colors.grey : null,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$count',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (isExisting)
                                  Icon(
                                    Icons.check_circle,
                                    color: Colors.grey[400],
                                    size: 20,
                                  )
                                else
                                  Checkbox(
                                    value: isSelected,
                                    onChanged: (value) {
                                      setState(() {
                                        if (value == true) {
                                          _selectedTagIds.add(tagId);
                                        } else {
                                          _selectedTagIds.remove(tagId);
                                        }
                                      });
                                    },
                                  ),
                              ],
                            ),
                            onTap: isExisting
                                ? null
                                : () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedTagIds.remove(tagId);
                                      } else {
                                        _selectedTagIds.add(tagId);
                                      }
                                    });
                                  },
                          );
                        },
                      ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitTags,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('添加 (${_selectedTagIds.length})'),
        ),
      ],
    );
  }
}
