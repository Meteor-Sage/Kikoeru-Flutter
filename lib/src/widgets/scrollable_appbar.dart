import 'package:flutter/material.dart';

/// 可滚动 AppBar - 默认不显示分隔线，滚动时显示
class ScrollableAppBar extends StatefulWidget implements PreferredSizeWidget {
  const ScrollableAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.backgroundColor,
    this.foregroundColor,
    this.elevation,
    this.toolbarHeight = kToolbarHeight,
    this.flexibleSpace,
    this.bottom,
    this.automaticallyImplyLeading = true,
    this.titleSpacing,
    this.centerTitle,
  });

  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? elevation;
  final double toolbarHeight;
  final Widget? flexibleSpace;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;
  final double? titleSpacing;
  final bool? centerTitle;

  @override
  State<ScrollableAppBar> createState() => _ScrollableAppBarState();

  @override
  Size get preferredSize => Size.fromHeight(
        toolbarHeight + (bottom?.preferredSize.height ?? 0),
      );
}

class _ScrollableAppBarState extends State<ScrollableAppBar> {
  ScrollNotificationObserverState? _scrollNotificationObserver;
  bool _scrolledUnder = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollNotificationObserver?.removeListener(_handleScrollNotification);
    _scrollNotificationObserver = ScrollNotificationObserver.maybeOf(context);
    _scrollNotificationObserver?.addListener(_handleScrollNotification);
  }

  @override
  void dispose() {
    if (_scrollNotificationObserver != null) {
      _scrollNotificationObserver!.removeListener(_handleScrollNotification);
      _scrollNotificationObserver = null;
    }
    super.dispose();
  }

  void _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification &&
        defaultScrollNotificationPredicate(notification)) {
      final bool oldScrolledUnder = _scrolledUnder;
      final ScrollMetrics metrics = notification.metrics;
      switch (metrics.axisDirection) {
        case AxisDirection.up:
          // Scroll view is reversed
          _scrolledUnder = metrics.extentAfter > 0;
        case AxisDirection.down:
          _scrolledUnder = metrics.extentBefore > 0;
        case AxisDirection.right:
        case AxisDirection.left:
          // Scrolled under is only supported in the vertical axis
          break;
      }

      if (_scrolledUnder != oldScrolledUnder) {
        setState(() {
          // React to a change in scroll state
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: widget.title,
      leading: widget.leading,
      actions: widget.actions,
      backgroundColor: widget.backgroundColor,
      foregroundColor: widget.foregroundColor,
      elevation: widget.elevation ?? 0,
      scrolledUnderElevation: 0,
      toolbarHeight: widget.toolbarHeight,
      flexibleSpace: widget.flexibleSpace,
      automaticallyImplyLeading: widget.automaticallyImplyLeading,
      titleSpacing: widget.titleSpacing,
      centerTitle: widget.centerTitle,
      bottom: widget.bottom != null
          ? widget.bottom
          : PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 1,
                decoration: BoxDecoration(
                  gradient: _scrolledUnder
                      ? LinearGradient(
                          colors: [
                            Colors.grey.withOpacity(0.1),
                            Colors.grey.withOpacity(0.3),
                            Colors.grey.withOpacity(0.1),
                          ],
                        )
                      : LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            Colors.transparent,
                          ],
                        ),
                ),
              ),
            ),
    );
  }
}
