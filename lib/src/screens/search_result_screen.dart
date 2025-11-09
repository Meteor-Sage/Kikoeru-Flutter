import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/search_result_provider.dart';
import '../widgets/works_grid_view.dart';
import '../widgets/search_sort_dialog.dart';
import '../widgets/global_audio_player_wrapper.dart';

class SearchResultScreen extends ConsumerStatefulWidget {
  final String keyword;
  final String? searchTypeLabel;
  final Map<String, dynamic>? searchParams;

  const SearchResultScreen({
    super.key,
    required this.keyword,
    this.searchTypeLabel,
    this.searchParams,
  });

  @override
  ConsumerState<SearchResultScreen> createState() => _SearchResultScreenState();
}

class _SearchResultScreenState extends ConsumerState<SearchResultScreen> {
  final TextEditingController _pageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showPagination = false;

  @override
  void initState() {
    super.initState();
    print(
        '[SearchResult] Screen initialized with keyword: ${widget.keyword}, type: ${widget.searchTypeLabel}');
    _scrollController.addListener(_onScroll);
    // Load initial data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print(
          '[SearchResult] Starting search with params: ${widget.searchParams}');
      ref.read(searchResultProvider.notifier).initializeSearch(
            keyword: widget.keyword,
            searchParams: widget.searchParams,
          );
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final isNearBottom = _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200;

    // 显示/隐藏分页控件
    if (isNearBottom != _showPagination) {
      setState(() {
        _showPagination = isNearBottom;
      });
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _showSortDialog(BuildContext context) {
    final state = ref.read(searchResultProvider);
    showDialog(
      context: context,
      builder: (context) => SearchSortDialog(
        currentOption: state.sortOption,
        currentDirection: state.sortDirection,
        onSort: (option, direction) {
          ref.read(searchResultProvider.notifier).updateSort(option, direction);
        },
      ),
    );
  }

  Icon _getLayoutIcon(SearchLayoutType layoutType) {
    switch (layoutType) {
      case SearchLayoutType.bigGrid:
        return const Icon(Icons.grid_3x3);
      case SearchLayoutType.smallGrid:
        return const Icon(Icons.view_list);
      case SearchLayoutType.list:
        return const Icon(Icons.view_agenda);
    }
  }

  String _getLayoutTooltip(SearchLayoutType layoutType) {
    switch (layoutType) {
      case SearchLayoutType.bigGrid:
        return '切换到小网格视图';
      case SearchLayoutType.smallGrid:
        return '切换到列表视图';
      case SearchLayoutType.list:
        return '切换到大网格视图';
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchResultProvider);

    return GlobalAudioPlayerWrapper(
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          actions: [
            IconButton(
              icon: _getLayoutIcon(searchState.layoutType),
              iconSize: 22,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: () =>
                  ref.read(searchResultProvider.notifier).toggleLayoutType(),
              tooltip: _getLayoutTooltip(searchState.layoutType),
            ),
            IconButton(
              icon: Icon(
                searchState.subtitleFilter == 1
                    ? Icons.closed_caption
                    : Icons.closed_caption_disabled,
                color: searchState.subtitleFilter == 1
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              iconSize: 22,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: () => ref
                  .read(searchResultProvider.notifier)
                  .toggleSubtitleFilter(),
              tooltip: searchState.subtitleFilter == 1 ? '显示全部作品' : '仅显示带字幕作品',
            ),
            IconButton(
              icon: const Icon(Icons.sort),
              iconSize: 22,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: () => _showSortDialog(context),
              tooltip: '排序',
            ),
          ],
        ),
        body: Column(
          children: [
            // 搜索信息行
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _buildSearchInfo(context, searchState),
              ),
            ),
            // 搜索结果内容
            Expanded(
              child: _buildBody(searchState),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchInfo(BuildContext context, SearchResultState searchState) {
    // 检查是否有详细的搜索条件
    final conditions = widget.searchParams?['conditions'] as List?;
    final minRate = widget.searchParams?['minRate'] as num?;
    final ageRating = widget.searchParams?['ageRating'] as String?;
    final salesRange = widget.searchParams?['salesRange'] as String?;

    // 如果有详细条件，显示为芯片
    if (conditions != null && conditions.isNotEmpty) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // 搜索条件芯片
          ...conditions.map((condition) {
            final type = condition['type'] as String;
            final value = condition['value'] as String;
            final isExclude = condition['isExclude'] as bool? ?? false;
            // RJ号需要添加RJ前缀显示
            final displayValue = type == 'RJ号' ? 'RJ$value' : value;

            return Chip(
              avatar: Icon(
                isExclude
                    ? Icons.remove_circle_outline
                    : _getConditionIcon(type),
                size: 16,
              ),
              label: Text(
                '$type: $displayValue',
                style: const TextStyle(fontSize: 13),
              ),
              backgroundColor: isExclude
                  ? Theme.of(context).colorScheme.errorContainer
                  : Theme.of(context).colorScheme.secondaryContainer,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              side: BorderSide.none,
            );
          }),

          // 高级筛选条件芯片
          if (minRate != null && minRate > 0)
            Chip(
              avatar: const Icon(Icons.star, size: 16),
              label: Text(
                '评分 ≥ ${minRate.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 13),
              ),
              backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              side: BorderSide.none,
            ),
          if (ageRating != null)
            Chip(
              avatar: const Icon(Icons.shield, size: 16),
              label: Text(
                ageRating,
                style: const TextStyle(fontSize: 13),
              ),
              backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              side: BorderSide.none,
            ),
          if (salesRange != null)
            Chip(
              avatar: const Icon(Icons.trending_up, size: 16),
              label: Text(
                salesRange,
                style: const TextStyle(fontSize: 13),
              ),
              backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              side: BorderSide.none,
            ),

          // 结果统计
          if (searchState.totalCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                '共 ${searchState.totalCount} 个结果',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      );
    }

    // 原有的简单显示方式（兼容旧逻辑）
    String searchInfo = widget.keyword;
    if (widget.searchTypeLabel != null) {
      searchInfo = '${widget.searchTypeLabel}: $searchInfo';
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search,
                size: 18,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                searchInfo,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (searchState.totalCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.numbers,
                  size: 18,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 4),
                Text(
                  '${searchState.totalCount} 个结果',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBody(SearchResultState searchState) {
    if (searchState.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              '搜索失败',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              searchState.error!,
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () =>
                  ref.read(searchResultProvider.notifier).refresh(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (searchState.works.isEmpty && searchState.isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在搜索...'),
          ],
        ),
      );
    }

    if (searchState.works.isEmpty && !searchState.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '未找到相关作品',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
      );
    }

    return WorksGridView(
      works: searchState.works,
      layoutType: searchState.layoutType.toWorksLayoutType(),
      scrollController: _scrollController,
      isLoading: searchState.isLoading,
      paginationWidget:
          _showPagination ? _buildPaginationBar(searchState) : null,
    );
  }

  Widget _buildPaginationBar(SearchResultState searchState) {
    final maxPage = _calculateTotalPages(searchState);

    // 如果总数小于等于20，显示到底提示
    if (searchState.totalCount <= 20) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 16,
              color: Colors.grey.shade600,
            ),
            const SizedBox(width: 8),
            Text(
              '已经到底啦~杂库~',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 页码和总数信息
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '第 ${searchState.currentPage} / $maxPage 页',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '共 ${searchState.totalCount} 条',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 按钮组
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 上一页
              _buildPageButton(
                icon: Icons.chevron_left,
                label: '上一页',
                enabled: searchState.currentPage > 1 && !searchState.isLoading,
                onPressed: () {
                  ref
                      .read(searchResultProvider.notifier)
                      .goToPage(searchState.currentPage - 1);
                  _scrollToTop();
                },
              ),
              const SizedBox(width: 8),

              // 跳转输入
              _buildPageJumpButton(searchState, maxPage),
              const SizedBox(width: 8),

              // 下一页
              _buildPageButton(
                label: '下一页',
                icon: Icons.chevron_right,
                enabled: searchState.hasMore && !searchState.isLoading,
                iconOnRight: true,
                onPressed: () {
                  ref
                      .read(searchResultProvider.notifier)
                      .goToPage(searchState.currentPage + 1);
                  _scrollToTop();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 分页按钮
  Widget _buildPageButton({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onPressed,
    bool iconOnRight = false,
  }) {
    final iconWidget = Icon(
      icon,
      size: 18,
      color: enabled
          ? Theme.of(context).colorScheme.onPrimaryContainer
          : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
    );

    final textWidget = Text(
      label,
      style: TextStyle(
        fontSize: 13,
        color: enabled
            ? Theme.of(context).colorScheme.onPrimaryContainer
            : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
      ),
    );

    return Material(
      color: enabled
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: iconOnRight
                ? [textWidget, const SizedBox(width: 4), iconWidget]
                : [iconWidget, const SizedBox(width: 4), textWidget],
          ),
        ),
      ),
    );
  }

  // 页码跳转按钮
  Widget _buildPageJumpButton(SearchResultState searchState, int maxPage) {
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _showPageJumpDialog(searchState, maxPage),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.edit_location_alt,
                size: 18,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 4),
              Text(
                '跳转',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 显示页码跳转对话框
  void _showPageJumpDialog(SearchResultState searchState, int maxPage) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('跳转到指定页'),
        content: TextField(
          controller: _pageController,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '页码',
            hintText: '输入 1-$maxPage',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.tag),
          ),
          onSubmitted: (value) {
            Navigator.of(context).pop();
            _handlePageJump(value, maxPage);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _handlePageJump(_pageController.text, maxPage);
            },
            child: const Text('跳转'),
          ),
        ],
      ),
    );
  }

  // 处理页码跳转
  void _handlePageJump(String value, int maxPage) {
    final page = int.tryParse(value);
    if (page != null && page > 0 && page <= maxPage) {
      ref.read(searchResultProvider.notifier).goToPage(page);
      _pageController.clear();
      _scrollToTop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('请输入 1-$maxPage 之间的页码'),
          duration: const Duration(seconds: 2),
        ),
      );
      _pageController.clear();
    }
  }

  int _calculateTotalPages(SearchResultState searchState) {
    if (searchState.totalCount == 0) return 1;
    return (searchState.totalCount / searchState.pageSize).ceil();
  }

  IconData _getConditionIcon(String type) {
    switch (type) {
      case '关键词':
        return Icons.search;
      case 'RJ号':
        return Icons.tag;
      case '标签':
        return Icons.label;
      case '社团':
        return Icons.group;
      case '声优':
        return Icons.person;
      default:
        return Icons.search;
    }
  }
}
