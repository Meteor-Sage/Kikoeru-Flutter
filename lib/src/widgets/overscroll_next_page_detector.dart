import 'package:flutter/material.dart';

/// A widget that detects overscroll at the bottom of a ScrollView and triggers an action.
/// It provides a visual "stretch" feedback and a text prompt.
class OverscrollNextPageDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback? onNextPage;
  final bool hasNextPage;
  final bool isLoading;
  final String promptText;
  final String releaseText;
  final double triggerThreshold;

  const OverscrollNextPageDetector({
    super.key,
    required this.child,
    this.onNextPage,
    this.hasNextPage = false,
    this.isLoading = false,
    this.promptText = '继续下拉跳转下一页',
    this.releaseText = '释放跳转下一页',
    this.triggerThreshold = 100.0,
  });

  @override
  State<OverscrollNextPageDetector> createState() =>
      _OverscrollNextPageDetectorState();
}

class _OverscrollNextPageDetectorState
    extends State<OverscrollNextPageDetector> {
  double _overscroll = 0;
  bool _isTriggered = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: widget.child,
        ),
        if (_overscroll > 0 && widget.hasNextPage && !widget.isLoading)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: _overscroll.clamp(0.0, 200.0),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withOpacity(0.5),
                  ],
                ),
              ),
              child: Opacity(
                opacity:
                    (_overscroll / widget.triggerThreshold).clamp(0.0, 1.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isTriggered
                          ? Icons.arrow_circle_up
                          : Icons.keyboard_double_arrow_up,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isTriggered ? widget.releaseText : widget.promptText,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!widget.hasNextPage || widget.isLoading) return false;

    if (notification is OverscrollNotification) {
      if (notification.overscroll > 0) {
        // Overscroll at the bottom
        setState(() {
          _overscroll += notification.overscroll / 2; // Dampen the effect
          if (_overscroll > widget.triggerThreshold) {
            _isTriggered = true;
          }
        });
      }
    } else if (notification is ScrollUpdateNotification) {
      // Handle scroll back when overscrolled
      if (_overscroll > 0 && notification.scrollDelta != null) {
        // If scrolling back up (delta < 0), reduce overscroll
        // Note: ScrollUpdateNotification doesn't always report delta correctly during overscroll on all platforms
        // But usually if user drags back, we get updates.
        // Actually, for ClampingScrollPhysics, we might not get OverscrollNotification if we are just holding it?
        // Let's rely on OverscrollNotification for accumulation.
        // But we need to reduce it if user scrolls back.

        // If we are overscrolled, and user drags down (scrollDelta < 0), we should reduce _overscroll.
        // However, notification.scrollDelta might be 0 if it's just overscroll update?
      }
    } else if (notification is ScrollEndNotification) {
      if (_isTriggered) {
        widget.onNextPage?.call();
      }
      // Reset
      setState(() {
        _overscroll = 0;
        _isTriggered = false;
      });
    }

    return false;
  }
}
