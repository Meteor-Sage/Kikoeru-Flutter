import 'package:flutter/material.dart';
import '../screens/search_result_screen.dart';

class CircleChip extends StatelessWidget {
  final int circleId;
  final String circleName;
  final VoidCallback? onDeleted;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool compact;
  final double? fontSize;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;
  final FontWeight? fontWeight;

  const CircleChip({
    super.key,
    required this.circleId,
    required this.circleName,
    this.onDeleted,
    this.onTap,
    this.onLongPress,
    this.compact = false,
    this.fontSize,
    this.padding,
    this.borderRadius,
    this.fontWeight,
  });

  @override
  Widget build(BuildContext context) {
    // 如果提供了自定义样式参数，使用自定义样式
    if (fontSize != null || padding != null || borderRadius != null) {
      return GestureDetector(
        onTap: onTap ??
            () {
              print('[CircleChip] Clicked circle: $circleName, id: $circleId');
              // 默认跳转到社团搜索结果页面
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SearchResultScreen(
                    keyword: circleName,
                    searchTypeLabel: '社团',
                    searchParams: {
                      'circleId': circleId,
                      'circleName': circleName
                    },
                  ),
                ),
              );
            },
        onLongPress: onLongPress,
        child: Container(
          padding:
              padding ?? const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(borderRadius ?? 12),
          ),
          child: Text(
            circleName,
            style: TextStyle(
              fontSize: fontSize ?? 11,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
              fontWeight: fontWeight ?? FontWeight.w500,
            ),
          ),
        ),
      );
    }

    // 使用默认的 Chip 样式
    if (onDeleted != null) {
      // 如果有删除功能，使用 InputChip
      return InputChip(
        label: Text(circleName),
        onPressed: onTap ??
            () {
              print('[CircleChip] Clicked circle: $circleName, id: $circleId');
              // 默认跳转到社团搜索结果页面
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SearchResultScreen(
                    keyword: circleName,
                    searchTypeLabel: '社团',
                    searchParams: {
                      'circleId': circleId,
                      'circleName': circleName
                    },
                  ),
                ),
              );
            },
        onDeleted: onDeleted,
        deleteIcon: const Icon(Icons.close, size: 16),
        visualDensity: compact ? VisualDensity.compact : null,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
        ),
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        labelStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
        deleteIconColor: Theme.of(context).colorScheme.onSecondaryContainer,
      );
    }

    // 默认的 ActionChip
    return ActionChip(
      label: Text(circleName),
      onPressed: onTap ??
          () {
            print('[CircleChip] Clicked circle: $circleName, id: $circleId');
            // 默认跳转到社团搜索结果页面
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SearchResultScreen(
                  keyword: circleName,
                  searchTypeLabel: '社团',
                  searchParams: {
                    'circleId': circleId,
                    'circleName': circleName
                  },
                ),
              ),
            );
          },
      visualDensity: compact ? VisualDensity.compact : null,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide(
        color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
      ),
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      labelStyle: TextStyle(
        color: Theme.of(context).colorScheme.onSecondaryContainer,
      ),
    );
  }
}
