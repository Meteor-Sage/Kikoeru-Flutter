import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/search_type.dart';
import '../providers/auth_provider.dart';
import 'search_result_screen.dart';

// 搜索条件项
class SearchCondition {
  final String id;
  final SearchType type;
  final String value;
  final bool isExclude; // 是否为排除模式

  SearchCondition({
    required this.id,
    required this.type,
    required this.value,
    this.isExclude = false,
  });

  String toSearchString() {
    switch (type) {
      case SearchType.keyword:
        return value;
      case SearchType.rjNumber:
        // RJ号直接添加RJ前缀（用户只输入数字）
        return 'RJ$value';
      case SearchType.tag:
        return isExclude ? '\$-tag:$value\$' : '\$tag:$value\$';
      case SearchType.circle:
        return isExclude ? '\$-circle:$value\$' : '\$circle:$value\$';
      case SearchType.va:
        return isExclude ? '\$-va:$value\$' : '\$va:$value\$';
    }
  }
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with AutomaticKeepAliveClientMixin {
  final _searchController = TextEditingController();
  final _conditionsScrollController = ScrollController(); // 用于搜索条件横向滚动
  final List<SearchCondition> _searchConditions = [];
  Key _autocompleteKey = UniqueKey(); // 用于强制刷新 Autocomplete
  FocusNode _searchFocusNode =
      FocusNode(); // 用于控制焦点（非 final，因为会在 Autocomplete 中重新赋值）

  SearchType _currentSearchType = SearchType.keyword;
  bool _isExcludeMode = false; // 是否处于反选（排除）模式
  double _minRate = 0;
  AgeRating _ageRating = AgeRating.all;
  SalesRange _salesRange = SalesRange.all;
  bool _showAdvancedFilters = false;

  // 建议列表数据（使用原始 JSON 以保留 count 字段）
  List<Map<String, dynamic>> _allTags = [];
  List<Map<String, dynamic>> _allVas = [];
  List<Map<String, dynamic>> _allCircles = [];
  bool _isLoadingSuggestions = false;

  @override
  bool get wantKeepAlive => true; // 保持状态不被销毁

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  @override
  void dispose() {
    _conditionsScrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // 加载建议数据
  Future<void> _loadSuggestions() async {
    if (_currentSearchType == SearchType.keyword ||
        _currentSearchType == SearchType.rjNumber) {
      return; // 关键词和RJ号不需要建议列表
    }

    setState(() => _isLoadingSuggestions = true);

    try {
      final api = ref.read(kikoeruApiServiceProvider);

      switch (_currentSearchType) {
        case SearchType.tag:
          if (_allTags.isEmpty) {
            final data = await api.getAllTags();
            _allTags = List<Map<String, dynamic>>.from(data);
            // 按 count 字段从大到小排序
            _allTags
                .sort((a, b) => (b['count'] ?? 0).compareTo(a['count'] ?? 0));
          }
          break;
        case SearchType.va:
          if (_allVas.isEmpty) {
            final data = await api.getAllVas();
            _allVas = List<Map<String, dynamic>>.from(data);
            // 按 count 字段从大到小排序
            _allVas
                .sort((a, b) => (b['count'] ?? 0).compareTo(a['count'] ?? 0));
          }
          break;
        case SearchType.circle:
          if (_allCircles.isEmpty) {
            final data = await api.getAllCircles();
            _allCircles = List<Map<String, dynamic>>.from(data);
            // 按 count 字段从大到小排序
            _allCircles
                .sort((a, b) => (b['count'] ?? 0).compareTo(a['count'] ?? 0));
          }
          break;
        default:
          break;
      }

      // 数据加载完成后刷新 Autocomplete
      setState(() {
        _autocompleteKey = UniqueKey();
      });
    } catch (e) {
      print('加载建议列表失败: $e');
    } finally {
      setState(() => _isLoadingSuggestions = false);
    }
  }

  void _addSearchCondition() {
    final value = _searchController.text.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入搜索内容')),
      );
      return;
    }

    setState(() {
      _searchConditions.add(SearchCondition(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: _currentSearchType,
        value: value,
        isExclude: _isExcludeMode,
      ));
      _searchController.clear();
      // 添加后重置为正选模式
      _isExcludeMode = false;
    });

    // 取消焦点，关闭下拉框
    FocusScope.of(context).unfocus();

    // 自动滚动到最新添加的标签位置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_conditionsScrollController.hasClients) {
        _conditionsScrollController.animateTo(
          _conditionsScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _removeSearchCondition(String id) {
    setState(() {
      _searchConditions.removeWhere((condition) => condition.id == id);
    });
  }

  Future<void> _performSearch() async {
    if (_searchConditions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少添加一个搜索条件')),
      );
      return;
    }

    // 构建搜索关键词
    List<String> searchParts = [];
    for (var condition in _searchConditions) {
      searchParts.add(condition.toSearchString());
    }

    // 添加高级筛选条件
    if (_minRate > 0) {
      searchParts.add('\$rate:${_minRate.toInt()}\$');
    }
    if (_ageRating != AgeRating.all && _ageRating.value.isNotEmpty) {
      searchParts.add('\$age:${_ageRating.value}\$');
    }
    if (_salesRange != SalesRange.all && _salesRange.value > 0) {
      searchParts.add('\$sell:${_salesRange.value}\$');
    }

    final searchKeyword = searchParts.join(' ');

    // 构建搜索条件列表用于显示
    final searchParams = {
      'keyword': searchKeyword,
      'conditions': _searchConditions
          .map((c) => {
                'type': c.type.label,
                'value': c.value,
                'isExclude': c.isExclude,
              })
          .toList(),
    };

    // 添加高级筛选显示
    if (_minRate > 0) {
      searchParams['minRate'] = _minRate;
    }
    if (_ageRating != AgeRating.all) {
      searchParams['ageRating'] = _ageRating.label;
    }
    if (_salesRange != SalesRange.all) {
      searchParams['salesRange'] = _salesRange.label;
    }

    // 跳转到搜索结果页面
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SearchResultScreen(
            keyword: searchKeyword,
            searchTypeLabel: null, // 不使用单一标签
            searchParams: searchParams,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以保持状态
    final theme = Theme.of(context);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return GestureDetector(
      // 点击任何地方（包括 AppBar）都取消焦点，关闭下拉框
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('搜索', style: TextStyle(fontSize: 18)),
          actions: [
            // 筛选按钮移到右上角
            IconButton(
              icon: Icon(
                _showAdvancedFilters
                    ? Icons.filter_alt
                    : Icons.filter_alt_outlined,
                color: _showAdvancedFilters
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              iconSize: 22,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: () {
                setState(() {
                  _showAdvancedFilters = !_showAdvancedFilters;
                  // 关闭高级筛选时重置参数为默认值
                  if (!_showAdvancedFilters) {
                    _minRate = 0;
                    _ageRating = AgeRating.all;
                    _salesRange = SalesRange.all;
                  }
                });
              },
              tooltip: '筛选',
            ),
          ],
        ),
        resizeToAvoidBottomInset: true, // 自动调整以避免键盘遮挡
        body: isLandscape
            ? Container(
                color: theme.colorScheme.surface,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_showAdvancedFilters)
                      _buildAdvancedFiltersSidebar(theme),
                    Expanded(
                      flex: 8,
                      child: SingleChildScrollView(
                        child: Container(
                          padding: EdgeInsets.fromLTRB(
                            _showAdvancedFilters ? 8 : 16,
                            16,
                            16,
                            16,
                          ),
                          color: theme.colorScheme.surface,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _buildMainContentChildren(true),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  color: theme.colorScheme.surface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildMainContentChildren(false),
                  ),
                ),
              ),
      ), // Scaffold 的闭合
    ); // GestureDetector 的闭合
  }

  Widget _buildAdvancedFiltersSidebar(ThemeData theme) {
    return Flexible(
      flex: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '高级筛选',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: '隐藏高级筛选',
                        onPressed: () {
                          setState(() {
                            _showAdvancedFilters = false;
                            _minRate = 0;
                            _ageRating = AgeRating.all;
                            _salesRange = SalesRange.all;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ..._buildAdvancedFilterSections(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMainContentChildren(bool isLandscape) {
    final theme = Theme.of(context);

    return [
      if (_searchConditions.isNotEmpty) ...[
        Text(
          '搜索条件',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 40,
          child: ListView.builder(
            controller: _conditionsScrollController,
            scrollDirection: Axis.horizontal,
            itemCount: _searchConditions.length,
            itemBuilder: (context, index) {
              final condition = _searchConditions[index];
              final displayValue = condition.type == SearchType.rjNumber
                  ? 'RJ${condition.value}'
                  : condition.value;

              return Padding(
                padding: EdgeInsets.only(
                  right: index == _searchConditions.length - 1 ? 0 : 6,
                ),
                child: Chip(
                  avatar: Icon(
                    condition.isExclude
                        ? Icons.remove_circle_outline
                        : _getSearchTypeIcon(condition.type),
                    size: 16,
                  ),
                  label: Text(
                    '${condition.type.label}: $displayValue',
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: condition.isExclude
                      ? theme.colorScheme.errorContainer
                      : theme.colorScheme.secondaryContainer,
                  onDeleted: () => _removeSearchCondition(condition.id),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  side: BorderSide.none,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  labelPadding: const EdgeInsets.only(left: 4, right: 2),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
      Text(
        '添加搜索条件',
        style: theme.textTheme.titleSmall,
      ),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: SearchType.values.map((type) {
            final supportsExclude = type == SearchType.tag ||
                type == SearchType.va ||
                type == SearchType.circle;
            final isCurrentType = _currentSearchType == type;
            final buttonTextStyle = theme.textTheme.labelLarge!;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Theme(
                data: theme.copyWith(useMaterial3: false),
                child: ChoiceChip(
                  avatar: isCurrentType && _isExcludeMode && supportsExclude
                      ? Icon(
                          Icons.remove_circle_outline,
                          size: 18,
                          color: theme.colorScheme.onErrorContainer,
                        )
                      : null,
                  label: Text(type.label),
                  selected: isCurrentType,
                  showCheckmark:
                      !(isCurrentType && _isExcludeMode && supportsExclude),
                  selectedColor:
                      isCurrentType && _isExcludeMode && supportsExclude
                          ? theme.colorScheme.errorContainer
                          : theme.colorScheme.primary,
                  labelStyle: buttonTextStyle.copyWith(
                    color: isCurrentType
                        ? (isCurrentType && _isExcludeMode && supportsExclude
                            ? theme.colorScheme.onErrorContainer
                            : theme.colorScheme.onPrimary)
                        : theme.colorScheme.onSurface,
                  ),
                  checkmarkColor: theme.colorScheme.onPrimary,
                  onSelected: (selected) {
                    setState(() {
                      if (isCurrentType && supportsExclude) {
                        _isExcludeMode = !_isExcludeMode;
                      } else {
                        _currentSearchType = type;
                        _isExcludeMode = false;
                        _searchController.clear();
                        _autocompleteKey = UniqueKey();
                        if (supportsExclude) {
                          _loadSuggestions();
                        }
                      }
                    });
                  },
                ),
              ),
            );
          }).toList(),
        ),
      ),
      if (_currentSearchType == SearchType.tag ||
          _currentSearchType == SearchType.va ||
          _currentSearchType == SearchType.circle)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Icon(
                _isExcludeMode
                    ? Icons.remove_circle_outline
                    : Icons.info_outline,
                size: 14,
                color: _isExcludeMode
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _isExcludeMode
                      ? '当前为排除模式：将排除包含该${_currentSearchType.label}的作品'
                      : '提示：再次点击"${_currentSearchType.label}"可切换为排除模式',
                  style: TextStyle(
                    fontSize: 12,
                    color: _isExcludeMode
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: (_currentSearchType == SearchType.tag ||
                    _currentSearchType == SearchType.va ||
                    _currentSearchType == SearchType.circle)
                ? Autocomplete<String>(
                    key: _autocompleteKey,
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      List<Map<String, dynamic>> sourceList;
                      switch (_currentSearchType) {
                        case SearchType.tag:
                          sourceList = _allTags;
                          break;
                        case SearchType.va:
                          sourceList = _allVas;
                          break;
                        case SearchType.circle:
                          sourceList = _allCircles;
                          break;
                        default:
                          sourceList = [];
                      }

                      List<Map<String, dynamic>> filteredList;
                      if (textEditingValue.text.trim().isEmpty) {
                        filteredList = sourceList.toList();
                      } else {
                        final query =
                            textEditingValue.text.trim().toLowerCase();
                        filteredList = sourceList.where((item) {
                          final name =
                              (item['name'] ?? item['title'] ?? '').toString();
                          return name.toLowerCase().contains(query);
                        }).toList();
                      }

                      return filteredList.map((item) {
                        final name =
                            (item['name'] ?? item['title'] ?? '').toString();
                        final count = item['count'] ?? 0;
                        return '$name ($count)';
                      });
                    },
                    optionsMaxHeight: 300,
                    onSelected: (String selection) {
                      final name =
                          selection.substring(0, selection.lastIndexOf(' ('));
                      _searchController.text = name;
                      _addSearchCondition();
                    },
                    fieldViewBuilder:
                        (context, controller, focusNode, onSubmitted) {
                      _searchFocusNode = focusNode;
                      controller.text = _searchController.text;
                      controller.addListener(() {
                        _searchController.text = controller.text;
                      });
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          hintText: _currentSearchType.hint,
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _isLoadingSuggestions
                              ? const Padding(
                                  padding: EdgeInsets.all(12.0),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          onSubmitted();
                          _addSearchCondition();
                        },
                      );
                    },
                  )
                : TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: _currentSearchType.hint,
                      prefixIcon: const Icon(Icons.search),
                      prefixText: _currentSearchType == SearchType.rjNumber
                          ? 'RJ'
                          : null,
                      prefixStyle: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    keyboardType: _currentSearchType == SearchType.rjNumber
                        ? TextInputType.number
                        : TextInputType.text,
                    inputFormatters: _currentSearchType == SearchType.rjNumber
                        ? [FilteringTextInputFormatter.digitsOnly]
                        : null,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addSearchCondition(),
                  ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _addSearchCondition,
              icon: const Icon(Icons.add),
              label: const Text('添加'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (!isLandscape && _showAdvancedFilters) ...[
        const Divider(),
        const SizedBox(height: 8),
        ..._buildAdvancedFilterSections(),
      ],
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _searchConditions.isEmpty ? null : _performSearch,
          icon: const Icon(Icons.search),
          label: Text(
            _searchConditions.isEmpty
                ? '请先添加搜索条件'
                : '搜索 (${_searchConditions.length} 个条件)',
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildAdvancedFilterSections() {
    final theme = Theme.of(context);

    return [
      Row(
        children: [
          const Icon(Icons.star, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '最低评分: ${_minRate.toStringAsFixed(2)} 星',
                  style: theme.textTheme.bodyMedium,
                ),
                Slider(
                  value: _minRate,
                  min: 0,
                  max: 5,
                  divisions: 20,
                  label: _minRate.toStringAsFixed(2),
                  onChanged: (value) => setState(() => _minRate = value),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<AgeRating>(
              value: _ageRating,
              decoration: InputDecoration(
                labelText: '年龄分级',
                prefixIcon: const Icon(Icons.shield),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                isDense: true,
              ),
              items: AgeRating.values.map((rating) {
                return DropdownMenuItem(
                  value: rating,
                  child: Text(rating.label),
                );
              }).toList(),
              onChanged: (value) =>
                  setState(() => _ageRating = value ?? AgeRating.all),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<SalesRange>(
              value: _salesRange,
              decoration: InputDecoration(
                labelText: '销量',
                prefixIcon: const Icon(Icons.trending_up),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                isDense: true,
              ),
              items: SalesRange.values.map((range) {
                return DropdownMenuItem(
                  value: range,
                  child: Text(range.label),
                );
              }).toList(),
              onChanged: (value) =>
                  setState(() => _salesRange = value ?? SalesRange.all),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
    ];
  }

  IconData _getSearchTypeIcon(SearchType type) {
    switch (type) {
      case SearchType.keyword:
        return Icons.search;
      case SearchType.rjNumber:
        return Icons.tag;
      case SearchType.tag:
        return Icons.label;
      case SearchType.circle:
        return Icons.group;
      case SearchType.va:
        return Icons.person;
    }
  }
}
