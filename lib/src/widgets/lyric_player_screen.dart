import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lyric.dart';
import '../providers/audio_provider.dart';
import '../providers/lyric_provider.dart';

class LyricPlayerScreen extends ConsumerStatefulWidget {
  const LyricPlayerScreen({super.key});

  @override
  ConsumerState<LyricPlayerScreen> createState() => _LyricPlayerScreenState();
}

class _LyricPlayerScreenState extends ConsumerState<LyricPlayerScreen> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  int? _currentLyricIndex;
  bool _autoScroll = true;
  bool _isInitialScroll = true;

  @override
  void initState() {
    super.initState();
    // 界面加载完成后，滚动到当前歌词位置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _performInitialScroll();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _itemKeys.clear();
    super.dispose();
  }

  // 获取或创建指定索引的 GlobalKey
  GlobalKey _getKeyForIndex(int index) {
    if (!_itemKeys.containsKey(index)) {
      _itemKeys[index] = GlobalKey();
    }
    return _itemKeys[index]!;
  }

  void _performInitialScroll() {
    if (!mounted || !_scrollController.hasClients) return;

    final lyricState = ref.read(lyricControllerProvider);
    final position = ref.read(positionProvider).valueOrNull;

    if (position != null && lyricState.lyrics.isNotEmpty) {
      final adjustedLyrics = lyricState.adjustedLyrics;
      final currentIndex = _getCurrentLyricIndex(position, adjustedLyrics);
      if (currentIndex >= 0) {
        _currentLyricIndex = currentIndex;
        _isInitialScroll = false;
        // 使用混合滚动策略
        _scrollToLyricHybrid(currentIndex, immediate: true);
      }
    }
  }

  void _scrollToCurrentLyric(int index, List<LyricLine> lyrics) {
    if (!_autoScroll || !_scrollController.hasClients) return;
    _scrollToLyricHybrid(index, immediate: _isInitialScroll);
    _isInitialScroll = false;
  }

  // 混合滚动策略：先计算滚动触发渲染，再精确定位
  void _scrollToLyricHybrid(int index, {bool immediate = false}) {
    final key = _getKeyForIndex(index);
    final context = key.currentContext;

    // 如果 Widget 已渲染，直接使用精确方式
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: immediate ? Duration.zero : const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      // Widget 未渲染，先用计算方式滚动到大致位置
      _scrollToApproximatePosition(index, immediate: immediate).then((_) {
        // 等待渲染完成后，再精确定位
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final newContext = key.currentContext;
          if (newContext != null && mounted) {
            Scrollable.ensureVisible(
              newContext,
              alignment: 0.5,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          } else if (mounted) {
            _nudgeAndRetry(index);
          }
        });
      });
    }
  }

  // 如果估算位置偏差过大，尝试向上/下轻推一个屏幕高度再检测
  Future<void> _nudgeAndRetry(int index) async {
    if (!_scrollController.hasClients) return;

    final key = _getKeyForIndex(index);
    if (key.currentContext != null) {
      return; // 已经渲染到视图中，无需处理
    }

    final viewport = _scrollController.position.viewportDimension;
    final currentOffset = _scrollController.position.pixels;
    final maxOffset = _scrollController.position.maxScrollExtent;

    Future<void> tryOffset(double offset) async {
      final target = (currentOffset + offset).clamp(0.0, maxOffset);
      await _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
      // 等待一帧，让懒加载有机会触发
      await Future.delayed(const Duration(milliseconds: 16));
      if (key.currentContext != null && mounted) {
        Scrollable.ensureVisible(
          key.currentContext!,
          alignment: 0.5,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    }

    // 先尝试向下轻推
    await tryOffset(viewport * 0.8);
    if (key.currentContext != null) return;

    // 再尝试向上轻推
    await tryOffset(-viewport * 0.8);
  }

  // 计算并滚动到大致位置（用于触发懒加载）
  Future<void> _scrollToApproximatePosition(int index,
      {bool immediate = false}) async {
    if (!_scrollController.hasClients) return;

    final lyricState = ref.read(lyricControllerProvider);
    final adjustedLyrics = lyricState.adjustedLyrics;
    final screenHeight = MediaQuery.of(context).size.height;

    // 使用精确估算计算目标位置
    final targetOffset = _calculateOffsetToIndex(index, adjustedLyrics);

    // 减去半个屏幕高度，让目标歌词居中
    final centeredOffset = targetOffset - screenHeight / 2;

    final clampedOffset = centeredOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    if (immediate) {
      _scrollController.jumpTo(clampedOffset);
      // 立即跳转后等待一帧以确保渲染
      await Future.delayed(const Duration(milliseconds: 50));
    } else {
      await _scrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  int _getCurrentLyricIndex(Duration position, List<LyricLine> lyrics) {
    for (int i = 0; i < lyrics.length; i++) {
      if (position >= lyrics[i].startTime && position < lyrics[i].endTime) {
        return i;
      }
    }
    return -1;
  }

  /// 估算单个歌词 item 的高度
  double _estimateItemHeight(String text, bool isActive, bool isPlaceholder) {
    // 基础组件高度
    const double verticalPadding = 24.0; // Container padding: 12 * 2
    const double lineHeight = 1.5; // Text height multiplier

    // 占位符固定高度
    if (isPlaceholder) {
      const double placeholderFontSize = 16.0;
      return verticalPadding + (placeholderFontSize * lineHeight);
    }

    // 文本样式参数
    final double fontSize = isActive ? 20.0 : 16.0;

    // 可用文本宽度 = 屏幕宽度 - 左右 padding
    final screenWidth = MediaQuery.of(context).size.width;
    const double horizontalPadding = 48.0; // ListView padding: 24 * 2
    final availableTextWidth = screenWidth - horizontalPadding;

    // 使用 TextPainter 计算实际文本高度
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          height: lineHeight,
        ),
      ),
      maxLines: null,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout(maxWidth: availableTextWidth);
    final textHeight = textPainter.height;

    return verticalPadding + textHeight;
  }

  /// 计算到目标索引的累积偏移量
  double _calculateOffsetToIndex(int targetIndex, List<LyricLine> lyrics) {
    double offset = 40.0; // ListView 顶部 padding

    for (int i = 0; i < targetIndex && i < lyrics.length; i++) {
      final isPlaceholder = lyrics[i].text.isEmpty;
      // 对于未渲染的 item，预测它是否会是激活状态（通常不会，用普通样式估算）
      offset += _estimateItemHeight(lyrics[i].text, false, isPlaceholder);
    }

    return offset;
  }

  @override
  Widget build(BuildContext context) {
    final lyricState = ref.watch(lyricControllerProvider);
    final position = ref.watch(positionProvider);
    final currentTrack = ref.watch(currentTrackProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('歌词'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: Icon(_autoScroll ? Icons.lock : Icons.lock_open),
            onPressed: () {
              setState(() {
                _autoScroll = !_autoScroll;
              });
            },
            tooltip: _autoScroll ? '锁定滚动' : '自动滚动',
          ),
        ],
      ),
      body: currentTrack.when(
        data: (track) {
          if (track == null) {
            return const Center(child: Text('没有正在播放的音频'));
          }

          if (lyricState.lyrics.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lyrics_outlined,
                    size: 80,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无歌词',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            );
          }

          return position.when(
            data: (pos) {
              // 使用调整后的歌词
              final adjustedLyrics = lyricState.adjustedLyrics;
              final currentIndex = _getCurrentLyricIndex(pos, adjustedLyrics);

              // 自动滚动到当前歌词
              if (currentIndex != _currentLyricIndex && currentIndex >= 0) {
                _currentLyricIndex = currentIndex;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToCurrentLyric(currentIndex, adjustedLyrics);
                });
              }

              return NotificationListener<UserScrollNotification>(
                onNotification: (notification) {
                  // 用户手动滚动时暂时禁用自动滚动
                  setState(() {
                    _autoScroll = false;
                  });
                  return false;
                },
                child: ListView.builder(
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                  itemCount: adjustedLyrics.length,
                  itemBuilder: (context, index) {
                    final lyric = adjustedLyrics[index];
                    final isActive = index == currentIndex;
                    // 空文本表示间隙占位符，显示 ♪
                    final isPlaceholder = lyric.text.isEmpty;

                    return GestureDetector(
                      key: _getKeyForIndex(index), // 添加 key 用于精确定位
                      onTap: isPlaceholder
                          ? null
                          : () {
                              // 点击歌词跳转到对应位置
                              ref
                                  .read(audioPlayerControllerProvider.notifier)
                                  .seek(lyric.startTime);
                              setState(() {
                                _autoScroll = true;
                              });
                            },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          isPlaceholder ? '♪' : lyric.text,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                color: isActive && !isPlaceholder
                                    ? Theme.of(context).colorScheme.primary
                                    : isPlaceholder
                                        ? Theme.of(context)
                                            .colorScheme
                                            .outline
                                            .withOpacity(0.3)
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.5),
                                fontWeight: isActive && !isPlaceholder
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: isActive && !isPlaceholder ? 20 : 16,
                                height: 1.5,
                              ),
                          textAlign: isPlaceholder
                              ? TextAlign.center
                              : TextAlign.start,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Center(child: Text('加载失败')),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('加载失败')),
      ),
    );
  }
}
