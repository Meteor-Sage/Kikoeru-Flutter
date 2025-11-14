import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/lyric.dart';
import '../../providers/audio_provider.dart';
import '../../providers/lyric_provider.dart';

/// 小歌词显示组件（在封面下方显示当前歌词）
class LyricDisplay extends ConsumerWidget {
  final String? albumName;

  const LyricDisplay({super.key, this.albumName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLyric = ref.watch(currentLyricTextProvider);
    final lyricState = ref.watch(lyricControllerProvider);

    // 如果有歌词，显示歌词
    if (lyricState.lyrics.isNotEmpty) {
      return Container(
        constraints: const BoxConstraints(
          minHeight: 23,
          maxHeight: 70,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        child: Center(
          child: SingleChildScrollView(
            child: Text(
              currentLyric ?? '♪',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                    fontSize: 14,
                  ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
    }

    // 没有歌词时显示专辑名
    if (albumName != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        child: Text(
          albumName!,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// 全屏歌词显示组件（横屏或竖屏全屏模式）
class FullLyricDisplay extends ConsumerStatefulWidget {
  final Duration? seekingPosition;
  final bool isPortrait;

  const FullLyricDisplay({
    super.key,
    this.seekingPosition,
    this.isPortrait = false,
  });

  @override
  ConsumerState<FullLyricDisplay> createState() => _FullLyricDisplayState();
}

class _FullLyricDisplayState extends ConsumerState<FullLyricDisplay> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  int? _currentLyricIndex;
  bool _autoScroll = true;

  @override
  void dispose() {
    _scrollController.dispose();
    _itemKeys.clear();
    super.dispose();
  }

  GlobalKey _getKeyForIndex(int index) {
    if (!_itemKeys.containsKey(index)) {
      _itemKeys[index] = GlobalKey();
    }
    return _itemKeys[index]!;
  }

  int _getCurrentLyricIndex(Duration position, List<LyricLine> lyrics) {
    for (int i = lyrics.length - 1; i >= 0; i--) {
      if (position >= lyrics[i].startTime) {
        return i;
      }
    }
    return -1;
  }

  /// 估算单个歌词 item 的高度
  double _estimateItemHeight(String text, BuildContext context, bool isActive) {
    const double verticalPadding = 24.0;
    const double verticalMargin = 8.0;
    const double lineHeight = 1.5;
    final double fontSize = isActive ? 18.0 : 16.0;

    final screenWidth = MediaQuery.of(context).size.width;
    final double lyricAreaWidth;
    final double outerPadding;

    if (widget.isPortrait) {
      lyricAreaWidth = screenWidth;
      outerPadding = 48.0;
    } else {
      lyricAreaWidth = screenWidth * 0.6;
      outerPadding = 0.0;
    }

    const double listViewPadding = 48.0;
    const double containerHorizontalPadding = 32.0;
    final availableTextWidth = lyricAreaWidth -
        outerPadding -
        listViewPadding -
        containerHorizontalPadding;

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

    return verticalPadding + textHeight + verticalMargin;
  }

  /// 计算到目标索引的累积偏移量
  double _calculateOffsetToIndex(
      int targetIndex, List<LyricLine> lyrics, BuildContext context) {
    double offset = 20.0;

    for (int i = 0; i < targetIndex && i < lyrics.length; i++) {
      offset += _estimateItemHeight(lyrics[i].text, context, false);
    }

    return offset;
  }

  void _scrollToLyric(int index, {bool animate = true, bool force = false}) {
    if (!_autoScroll || !_scrollController.hasClients) return;

    final key = _getKeyForIndex(index);
    final itemContext = key.currentContext;

    if (itemContext != null) {
      Scrollable.ensureVisible(
        itemContext,
        alignment: 0.5,
        duration: animate ? const Duration(milliseconds: 300) : Duration.zero,
        curve: Curves.easeOut,
      );
    } else if (force && mounted) {
      final lyricState = ref.read(lyricControllerProvider);
      final targetOffset =
          _calculateOffsetToIndex(index, lyricState.lyrics, context);
      final maxScroll = _scrollController.position.maxScrollExtent;
      final clampedOffset = targetOffset.clamp(0.0, maxScroll);

      _scrollController.jumpTo(clampedOffset);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final newContext = key.currentContext;
        if (newContext != null && mounted) {
          Scrollable.ensureVisible(
            newContext,
            alignment: 0.5,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _onLyricTap(int index) {
    final lyricState = ref.read(lyricControllerProvider);
    if (index >= 0 && index < lyricState.lyrics.length) {
      final targetTime = lyricState.lyrics[index].startTime;
      ref.read(audioPlayerControllerProvider.notifier).seek(targetTime);

      setState(() {
        _autoScroll = false;
      });

      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() {
            _autoScroll = true;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lyricState = ref.watch(lyricControllerProvider);
    final position = ref.watch(positionProvider);

    return position.when(
      data: (pos) {
        final displayPosition = widget.seekingPosition ?? pos;
        final currentIndex =
            _getCurrentLyricIndex(displayPosition, lyricState.lyrics);

        if (currentIndex != _currentLyricIndex && currentIndex >= 0) {
          final previousIndex = _currentLyricIndex;
          _currentLyricIndex = currentIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final isLargeJump = previousIndex == null ||
                (currentIndex - previousIndex).abs() > 5;
            final animate = widget.seekingPosition == null;

            _scrollToLyric(currentIndex, animate: animate, force: isLargeJump);
          });
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          itemCount: lyricState.lyrics.length,
          itemBuilder: (context, index) {
            final lyric = lyricState.lyrics[index];
            final isActive = index == currentIndex;
            final isPast = index < currentIndex;

            return GestureDetector(
              key: _getKeyForIndex(index),
              onTap: () => _onLyricTap(index),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: isActive
                      ? Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withOpacity(0.3)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  lyric.text,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: isActive
                            ? Theme.of(context).colorScheme.primary
                            : isPast
                                ? Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withOpacity(0.5)
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                        fontWeight:
                            isActive ? FontWeight.bold : FontWeight.normal,
                        fontSize: isActive ? 18 : 16,
                        height: 1.5,
                      ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('加载失败')),
    );
  }
}
