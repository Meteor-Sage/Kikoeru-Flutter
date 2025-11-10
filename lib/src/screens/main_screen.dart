import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/audio_provider.dart';
import '../widgets/audio_player_widget.dart';
import 'works_screen.dart';
import 'search_screen.dart';
import 'my_screen.dart';
import 'settings_screen.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _currentIndex = 0;

  // 使用 PageStorageBucket 来保存页面状态
  final PageStorageBucket _bucket = PageStorageBucket();

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = const [
      WorksScreen(key: PageStorageKey('works_screen')),
      SearchScreen(key: PageStorageKey('search_screen')),
      MyScreen(key: PageStorageKey('my_screen')),
      SettingsScreen(key: PageStorageKey('settings_screen')),
    ];
  }

  final List<NavigationDestination> _destinations = [
    const NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: '主页',
    ),
    const NavigationDestination(
      icon: Icon(Icons.search_outlined),
      selectedIcon: Icon(Icons.search),
      label: '搜索',
    ),
    const NavigationDestination(
      icon: Icon(Icons.favorite_border),
      selectedIcon: Icon(Icons.favorite),
      label: '我的',
    ),
    const NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: '设置',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    if (isLandscape) {
      // 横屏布局：使用 NavigationRail
      return Scaffold(
        body: Row(
          children: [
            // 侧边导航栏 - 添加 SingleChildScrollView 避免键盘弹出时像素重叠
            SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height,
                ),
                child: IntrinsicHeight(
                  child: NavigationRail(
                    selectedIndex: _currentIndex,
                    onDestinationSelected: (index) {
                      setState(() {
                        _currentIndex = index;
                      });
                    },
                    labelType: NavigationRailLabelType.selected,
                    destinations: _destinations
                        .map((dest) => NavigationRailDestination(
                              icon: dest.icon,
                              selectedIcon: dest.selectedIcon,
                              label: Text(dest.label),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            // 主内容区域
            Expanded(
              child: Column(
                children: [
                  // 主内容
                  Expanded(
                    child: PageStorage(
                      bucket: _bucket,
                      child: IndexedStack(
                        index: _currentIndex,
                        children: List.generate(_screens.length, (index) {
                          return HeroMode(
                            enabled: index == _currentIndex,
                            child: _screens[index],
                          );
                        }),
                      ),
                    ),
                  ),
                  // MiniPlayer
                  Consumer(
                    builder: (context, ref, child) {
                      final currentTrack = ref.watch(currentTrackProvider);
                      return currentTrack.when(
                        data: (track) => track != null
                            ? const MiniPlayer()
                            : const SizedBox.shrink(),
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 竖屏布局：使用 BottomNavigationBar
    return Scaffold(
      body: PageStorage(
        bucket: _bucket,
        child: IndexedStack(
          index: _currentIndex,
          children: List.generate(_screens.length, (index) {
            return HeroMode(
              enabled: index == _currentIndex,
              child: _screens[index],
            );
          }),
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // MiniPlayer
          Consumer(
            builder: (context, ref, child) {
              final currentTrack = ref.watch(currentTrackProvider);
              return currentTrack.when(
                data: (track) => track != null
                    ? const MiniPlayer()
                    : const SizedBox.shrink(),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              );
            },
          ),
          // NavigationBar
          NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            destinations: _destinations,
          ),
        ],
      ),
    );
  }
}
