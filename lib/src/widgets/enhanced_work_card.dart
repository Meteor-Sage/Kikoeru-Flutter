import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/work.dart';
import '../providers/auth_provider.dart';
import '../providers/my_reviews_provider.dart';
import '../screens/work_detail_screen.dart';
import 'tag_chip.dart';
import 'va_chip.dart';
import 'responsive_dialog.dart';

class EnhancedWorkCard extends ConsumerStatefulWidget {
  final Work work;
  final VoidCallback? onTap;
  final int crossAxisCount;

  const EnhancedWorkCard({
    super.key,
    required this.work,
    this.onTap,
    this.crossAxisCount = 2,
  });

  @override
  ConsumerState<EnhancedWorkCard> createState() => _EnhancedWorkCardState();
}

class _EnhancedWorkCardState extends ConsumerState<EnhancedWorkCard> {
  String? _progress; // 当前收藏状态
  bool _loadingProgress = false; // 是否在获取状态
  bool _updating = false; // 是否在更新状态

  @override
  void initState() {
    super.initState();
    _progress = widget.work.progress; // 初始来自传入的work
  }

  // 长按逻辑：获取最新详情(含 progress)，然后弹出编辑菜单
  Future<void> _onLongPress() async {
    if (_loadingProgress || _updating) return;
    setState(() => _loadingProgress = true);
    try {
      final api = ref.read(kikoeruApiServiceProvider);
      final json = await api.getWork(widget.work.id);
      final detailed = Work.fromJson(json);
      setState(() {
        _progress = detailed.progress; // 更新最新状态
        _loadingProgress = false;
      });
      _showEditSheet();
    } catch (e) {
      setState(() => _loadingProgress = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('获取状态失败: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  String _labelFor(String? value) {
    if (value == null) return '未收藏';
    final found = [
      MyReviewFilter.marked,
      MyReviewFilter.listening,
      MyReviewFilter.listened,
      MyReviewFilter.replay,
      MyReviewFilter.postponed,
    ].firstWhere(
      (f) => f.value == value,
      orElse: () => MyReviewFilter.all,
    );
    return found.label;
  }

  void _showEditSheet() {
    final filters = [
      MyReviewFilter.marked,
      MyReviewFilter.listening,
      MyReviewFilter.listened,
      MyReviewFilter.replay,
      MyReviewFilter.postponed,
    ];

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    if (isLandscape) {
      // 横屏模式：使用对话框形式，3+3两列布局
      showDialog(
        context: context,
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
                            '编辑收藏状态',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (_updating)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
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
                                children: filters.take(3).map((f) {
                                  final selected = _progress == f.value;
                                  return RadioListTile<String>(
                                    title: Text(f.label),
                                    value: f.value!,
                                    groupValue: _progress,
                                    onChanged: _updating
                                        ? null
                                        : (value) {
                                            Navigator.of(dialogContext).pop();
                                            _updateProgress(value);
                                          },
                                    selected: selected,
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
                                  ...filters.skip(3).map((f) {
                                    final selected = _progress == f.value;
                                    return RadioListTile<String>(
                                      title: Text(f.label),
                                      value: f.value!,
                                      groupValue: _progress,
                                      onChanged: _updating
                                          ? null
                                          : (value) {
                                              Navigator.of(dialogContext).pop();
                                              _updateProgress(value);
                                            },
                                      selected: selected,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 8),
                                    );
                                  }),
                                  if (_progress != null) ...[
                                    const Divider(height: 1),
                                    ListTile(
                                      leading: Icon(Icons.delete_outline,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error),
                                      title: Text('移除',
                                          style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error)),
                                      onTap: _updating
                                          ? null
                                          : () {
                                              Navigator.of(dialogContext).pop();
                                              _updateProgress(null);
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
      return;
    }

    // 竖屏模式：使用底部弹窗
    showResponsiveBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Text(
                      '编辑收藏状态',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    if (_updating)
                      const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ...filters.map((f) {
                final selected = _progress == f.value;
                return ListTile(
                  leading: Icon(
                      selected ? Icons.check_circle : Icons.circle_outlined,
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : null),
                  title: Text(f.label),
                  onTap: _updating ? null : () => _updateProgress(f.value!),
                  selected: selected,
                );
              }),
              if (_progress != null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error),
                  title: Text('移除',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                  onTap: _updating ? null : () => _updateProgress(null),
                ),
              ],
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  Future<void> _updateProgress(String? value) async {
    if (_updating) return;
    setState(() => _updating = true);
    final api = ref.read(kikoeruApiServiceProvider);
    try {
      if (value != null) {
        await api.updateReviewProgress(widget.work.id, progress: value);
        setState(() => _progress = value);
        if (mounted) {
          // 只在竖屏模式关闭底部弹窗，横屏模式已在点击时关闭对话框
          if (MediaQuery.of(context).orientation == Orientation.portrait) {
            Navigator.pop(context);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已设置为：${_labelFor(value)}'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        await api.deleteReview(widget.work.id);
        setState(() => _progress = null);
        if (mounted) {
          // 只在竖屏模式关闭底部弹窗，横屏模式已在点击时关闭对话框
          if (MediaQuery.of(context).orientation == Orientation.portrait) {
            Navigator.pop(context);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已移除标记'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('操作失败: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';

    final cardOnTap = widget.onTap ??
        () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => WorkDetailScreen(work: widget.work),
            ),
          );
        };

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    // 横屏模式：3列显示中等卡片，5列显示紧凑卡片
    // 竖屏模式：2列显示中等卡片，3列显示紧凑卡片
    if (widget.crossAxisCount >= 5 ||
        (widget.crossAxisCount == 3 && !isLandscape)) {
      return _buildCompactCard(context, host, token, cardOnTap);
    } else if (widget.crossAxisCount >= 2) {
      return _buildMediumCard(context, host, token, cardOnTap);
    } else {
      return _buildFullCard(context, host, token, cardOnTap);
    }
  }

  // 紧凑卡片 (3列布局)
  Widget _buildCompactCard(
      BuildContext context, String host, String token, VoidCallback cardOnTap) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.all(0),
      elevation: 8,
      child: InkWell(
        onTap: cardOnTap,
        onLongPress: _onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, // 让 Column 高度自适应
          children: [
            // 封面图片区域
            AspectRatio(
              aspectRatio: 1.0,
              child: Stack(
                children: [
                  _buildCoverImage(context, host, token),
                  // RJ号标签 (左上角)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: _buildRjTag(),
                  ),
                  // 日期标签 (右下角)
                  if (widget.work.release != null)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: _buildDateTag(),
                    ),
                ],
              ),
            ),
            // 信息区域 - 自适应高度
            Padding(
              padding: const EdgeInsets.all(6.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 标题
                  Text(
                    widget.work.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                          fontSize: 11,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 中等卡片 (2列布局)
  Widget _buildMediumCard(
      BuildContext context, String host, String token, VoidCallback cardOnTap) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.all(0),
      elevation: 8,
      child: InkWell(
        onTap: cardOnTap,
        onLongPress: _onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 封面区域
            AspectRatio(
              aspectRatio: 1.3,
              child: Stack(
                children: [
                  _buildCoverImage(context, host, token),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: _buildRjTag(),
                  ),
                  // 字幕标签 (左下角)
                  if (widget.work.hasSubtitle == true)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: _buildSubtitleTag(context),
                    ),
                  if (widget.work.release != null)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: _buildDateTag(),
                    ),
                ],
              ),
            ),
            // 信息区域 - 自适应高度
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 标题
                  Text(
                    widget.work.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                          fontSize: 12,
                        ),
                  ),
                  const SizedBox(height: 3),
                  // 社团名称
                  Text(
                    widget.work.name ?? '',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                          fontSize: 10,
                        ),
                  ),
                  const SizedBox(height: 3),
                  // 价格
                  if (widget.work.price != null)
                    Text(
                      '${widget.work.price} 日元',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.red[700],
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                    ),
                  // 评分信息
                  if (widget.work.rateAverage != null &&
                      widget.work.rateCount != null &&
                      widget.work.rateCount! > 0) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.star,
                          color: Colors.amber[700],
                          size: 12,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${widget.work.rateAverage!.toStringAsFixed(1)} (${widget.work.rateCount})',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.amber[700],
                                    fontWeight: FontWeight.w500,
                                    fontSize: 9,
                                  ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 4),
                  if (widget.work.vas != null && widget.work.vas!.isNotEmpty)
                    _buildVoiceActorsRow(context),
                  const SizedBox(height: 2),
                  if (widget.work.tags != null && widget.work.tags!.isNotEmpty)
                    _buildTagsRow(context),
                  const SizedBox(height: 2),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 完整卡片 (列表布局)
  Widget _buildFullCard(
      BuildContext context, String host, String token, VoidCallback cardOnTap) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      child: InkWell(
        onTap: cardOnTap,
        onLongPress: _onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：封面和标题
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 封面图片
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _buildCoverImage(context, host, token),
                        ),
                        // RJ号标签
                        Positioned(
                          top: 2,
                          left: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              'RJ${widget.work.id}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        // 字幕标签 (左下角)
                        if (widget.work.hasSubtitle == true)
                          Positioned(
                            bottom: 2,
                            left: 2,
                            child: _buildSubtitleTag(context),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 标题
                  Expanded(
                    child: Text(
                      widget.work.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            height: 1.3,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 第二行：其他信息
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 社团和价格行
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.work.name ?? '',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                        ),
                      ),
                      if (widget.work.price != null)
                        Text(
                          '${widget.work.price} 日元',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.red[700],
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // 日期和下载数
                  Row(
                    children: [
                      if (widget.work.release != null)
                        Text(
                          widget.work.release!,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[500],
                                  ),
                        ),
                      // 评分信息
                      if (widget.work.rateAverage != null &&
                          widget.work.rateCount != null &&
                          widget.work.rateCount! > 0) ...[
                        if (widget.work.release != null)
                          const SizedBox(width: 8),
                        Icon(
                          Icons.star,
                          color: Colors.amber[700],
                          size: 14,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${widget.work.rateAverage!.toStringAsFixed(1)} (${widget.work.rateCount})',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.amber[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                      ],
                      const Spacer(),
                      if (widget.work.dlCount != null)
                        Text(
                          '售出：${widget.work.dlCount}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[500],
                                  ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 声优
                  if (widget.work.vas != null && widget.work.vas!.isNotEmpty)
                    _buildVoiceActorsWrap(context),
                  const SizedBox(height: 6),
                  // 标签
                  if (widget.work.tags != null && widget.work.tags!.isNotEmpty)
                    _buildTagsWrap(context),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoverImage(BuildContext context, String host, String token) {
    // 使用缓存网络图片，减少滚动时的解码与网络开销，提升流畅度
    if (host.isEmpty) {
      return _buildPlaceholder(context);
    }

    final url = widget.work.getCoverImageUrl(host, token: token);
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    // 依据不同布局控制图片缓存尺寸，避免加载超大原图导致卡顿
    int targetWidth;
    switch (widget.crossAxisCount) {
      case 3:
        targetWidth =
            (MediaQuery.of(context).size.width / 3 * devicePixelRatio).round();
        break;
      case 2:
        targetWidth =
            (MediaQuery.of(context).size.width / 2 * devicePixelRatio).round();
        break;
      default:
        targetWidth = (80 * devicePixelRatio).round(); // 列表模式封面固定宽度
    }

    return Hero(
      tag: 'work_cover_${widget.work.id}',
      child: RepaintBoundary(
        child: CachedNetworkImage(
          imageUrl: url,
          cacheKey: 'work_cover_${widget.work.id}',
          memCacheWidth: targetWidth, // 降低解码分辨率，减少 GPU / CPU 压力
          fadeInDuration: const Duration(milliseconds: 120),
          fadeOutDuration: const Duration(milliseconds: 90),
          placeholderFadeInDuration: const Duration(milliseconds: 80),
          placeholder: (context, _) => _buildPlaceholder(context),
          errorWidget: (context, _, __) => _buildPlaceholder(context),
          imageBuilder: (context, imageProvider) => Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: imageProvider,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low, // 优化滚动时的重采样性能
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(
        Icons.audiotrack,
        color: Colors.grey,
        size: 32,
      ),
    );
  }

  Widget _buildRjTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'RJ${widget.work.id}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDateTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        widget.work.release!,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSubtitleTag(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(
        Icons.closed_caption,
        color: Colors.white,
        size: 14,
      ),
    );
  }

  Widget _buildTagsRow(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 14),
      child: Wrap(
        spacing: 3,
        runSpacing: 2,
        children: widget.work.tags!.map((tag) {
          return TagChip(
            tag: tag,
            fontSize: 10,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            borderRadius: 6,
            fontWeight: FontWeight.w500,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildVoiceActorsRow(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 14),
      child: Wrap(
        spacing: 3,
        runSpacing: 2,
        children: widget.work.vas!.map((va) {
          return VaChip(
            va: va,
            fontSize: 10,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            borderRadius: 6,
            fontWeight: FontWeight.w500,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTagsWrap(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: widget.work.tags!.map((tag) {
        return TagChip(
          tag: tag,
          fontSize: 11,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          borderRadius: 12,
          fontWeight: FontWeight.w500,
        );
      }).toList(),
    );
  }

  Widget _buildVoiceActorsWrap(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: widget.work.vas!.map((va) {
        return VaChip(
          va: va,
          fontSize: 11,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          borderRadius: 12,
          fontWeight: FontWeight.w500,
        );
      }).toList(),
    );
  }
}
