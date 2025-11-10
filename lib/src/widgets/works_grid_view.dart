import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../models/work.dart';
import '../providers/works_provider.dart';
import 'enhanced_work_card.dart';

class WorksGridView extends StatelessWidget {
  final List<Work> works;
  final LayoutType layoutType;
  final ScrollController? scrollController;
  final bool isLoading;
  final bool showEndMessage;
  final Widget? paginationWidget;

  const WorksGridView({
    super.key,
    required this.works,
    required this.layoutType,
    this.scrollController,
    this.isLoading = false,
    this.showEndMessage = false,
    this.paginationWidget,
  });

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    switch (layoutType) {
      case LayoutType.bigGrid:
        return _buildGridView(
          context,
          crossAxisCount: isLandscape ? 3 : 2,
        );
      case LayoutType.smallGrid:
        return _buildGridView(
          context,
          crossAxisCount: isLandscape ? 5 : 3,
        );
      case LayoutType.list:
        return _buildListView(context);
    }
  }

  Widget _buildGridView(BuildContext context, {required int crossAxisCount}) {
    return CustomScrollView(
      controller: scrollController,
      cacheExtent: 500,
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(8), // 统一为8
          sliver: SliverMasonryGrid.count(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 8, // 统一为8
            mainAxisSpacing: 8, // 统一为8
            childCount: works.length + (isLoading ? 1 : 0),
            itemBuilder: (context, index) {
              if (isLoading && index == works.length) {
                return const SizedBox(
                  height: 100, // 统一加载指示器高度
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final work = works[index];
              return RepaintBoundary(
                child: EnhancedWorkCard(
                  work: work,
                  crossAxisCount: crossAxisCount,
                ),
              );
            },
          ),
        ),

        // 到底提示
        if (showEndMessage)
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '已经到底啦~杂库~',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 分页控件
        if (paginationWidget != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 24), // 统一左右padding为8
            sliver: SliverToBoxAdapter(
              child: paginationWidget!,
            ),
          ),
      ],
    );
  }

  Widget _buildListView(BuildContext context) {
    return CustomScrollView(
      controller: scrollController,
      cacheExtent: 500,
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (isLoading && index == works.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                if (showEndMessage && index == works.length) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 24, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '已经到底啦~杂库~',
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final work = works[index];
                return RepaintBoundary(
                  child: EnhancedWorkCard(
                    work: work,
                    crossAxisCount: 1,
                  ),
                );
              },
              childCount:
                  works.length + (isLoading ? 1 : 0) + (showEndMessage ? 1 : 0),
            ),
          ),
        ),

        // 分页控件
        if (paginationWidget != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 24), // 统一左右padding为8
            sliver: SliverToBoxAdapter(
              child: paginationWidget!,
            ),
          ),
      ],
    );
  }
}
