import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/work.dart';
import '../providers/auth_provider.dart';
import '../widgets/scrollable_appbar.dart';
import '../widgets/tag_chip.dart';
import '../widgets/va_chip.dart';
import '../widgets/circle_chip.dart';
import '../widgets/offline_file_explorer_widget.dart';

/// 离线作品详情页 - 使用下载时保存的元数据展示作品信息
/// 不依赖网络请求，完全离线可用
class OfflineWorkDetailScreen extends ConsumerStatefulWidget {
  final Work work;
  final bool isOffline; // 标记是否为离线模式
  final String? localCoverPath; // 本地封面图片路径

  const OfflineWorkDetailScreen({
    super.key,
    required this.work,
    this.isOffline = true,
    this.localCoverPath,
  });

  @override
  ConsumerState<OfflineWorkDetailScreen> createState() =>
      _OfflineWorkDetailScreenState();
}

class _OfflineWorkDetailScreenState
    extends ConsumerState<OfflineWorkDetailScreen> {
  // 复制标题到剪贴板
  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制$label: $text'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // 构建网络封面图片（使用缓存）
  Widget _buildNetworkCover(Work work, String host, String token) {
    return CachedNetworkImage(
      imageUrl: '$host/api/cover/${work.id}',
      httpHeaders: {'Authorization': 'Bearer $token'},
      fit: BoxFit.contain,
      placeholder: (context, url) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.broken_image, size: 64),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final systemOverlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          brightness == Brightness.light ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemOverlayStyle,
      child: Scaffold(
        appBar: ScrollableAppBar(
          systemOverlayStyle: systemOverlayStyle,
          title: GestureDetector(
            onLongPress: () => _copyToClipboard('RJ${widget.work.id}', 'RJ号'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'RJ${widget.work.id}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                ),
                if (widget.isOffline) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange, width: 1),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.offline_bolt,
                            size: 12, color: Colors.orange),
                        SizedBox(width: 2),
                        Text(
                          '离线',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
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

    final work = widget.work;

    // 封面图片组件
    final coverWidget = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Hero(
        tag: 'offline_work_cover_${widget.work.id}',
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
                // 优先使用本地封面图片
                if (widget.localCoverPath != null &&
                    File(widget.localCoverPath!).existsSync())
                  Image.file(
                    File(widget.localCoverPath!),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      // 如果本地图片加载失败，回退到网络图片
                      return _buildNetworkCover(work, host, token);
                    },
                  )
                else
                  // 回退到网络图片（缓存）
                  _buildNetworkCover(work, host, token),
                // 字幕标签
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
                          fontWeight: FontWeight.bold,
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
          // 标题
          GestureDetector(
            onLongPress: () => _copyToClipboard(work.title, '标题'),
            child: Text(
              work.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
              textAlign: TextAlign.start,
              softWrap: true,
            ),
          ),
          const SizedBox(height: 8),

          // 离线提示
          if (widget.isOffline)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '离线模式：显示下载时保存的作品信息',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[800],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // 评分和销售信息
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // 评分信息
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .secondaryContainer
                      .withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
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
                    Text(
                      '(${work.rateCount ?? 0})',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
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

              // 销售数量
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
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (work.name != null && work.name!.isNotEmpty)
                  CircleChip(
                    circleId: work.circleId ?? 0,
                    circleName: work.name!,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    borderRadius: 6,
                    fontWeight: FontWeight.w500,
                    onLongPress: () => _copyToClipboard(work.name!, '社团'),
                  ),
                if (work.vas != null)
                  ...work.vas!.map((va) {
                    return VaChip(
                      va: va,
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
            const SizedBox(height: 16),
          ],

          // 作品描述
          if (work.description != null && work.description!.isNotEmpty) ...[
            Text(
              '作品简介',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              work.description!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 16),
          ],

          // 文件浏览器
          Text(
            '已下载文件',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(minHeight: 200, maxHeight: 400),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: OfflineFileExplorerWidget(
              work: work,
              fileTree: work.children != null
                  ? work.children!.map((e) {
                      if (e is Map<String, dynamic>) {
                        return e;
                      }
                      // 如果是 AudioFile 对象，转换为 Map
                      return e.toJson();
                    }).toList()
                  : null,
            ),
          ),
        ],
      ),
    );

    // 根据屏幕方向返回不同布局
    if (isLandscape) {
      // 横屏布局：左右分栏
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：封面
          Expanded(
            flex: 2,
            child: Center(
              child: coverWidget,
            ),
          ),
          // 右侧：信息（可滚动）
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(0),
              physics: const AlwaysScrollableScrollPhysics(),
              child: infoWidget,
            ),
          ),
        ],
      );
    } else {
      // 竖屏布局：上下排列
      return SingleChildScrollView(
        padding: const EdgeInsets.all(0),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            coverWidget,
            infoWidget,
          ],
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

  String _formatDuration(int minutes) {
    if (minutes < 60) {
      return '$minutes分钟';
    } else {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      return mins > 0 ? '${hours}小时${mins}分钟' : '${hours}小时';
    }
  }
}
