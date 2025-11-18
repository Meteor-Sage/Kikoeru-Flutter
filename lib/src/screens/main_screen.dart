import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/audio_provider.dart';
import '../providers/update_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/mini_player.dart';
import 'works_screen.dart';
import 'search_screen.dart';
import 'my_screen.dart';
import 'settings_screen.dart';
import '../providers/settings_provider.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _currentIndex = 0;
  static const int _settingsTabIndex = 3;

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

  List<NavigationDestination> _buildDestinations(bool showUpdateBadge) {
    return [
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
      NavigationDestination(
        icon: Badge(
          isLabelVisible: showUpdateBadge,
          child: const Icon(Icons.settings_outlined),
        ),
        selectedIcon: Badge(
          isLabelVisible: showUpdateBadge,
          child: const Icon(Icons.settings),
        ),
        label: '设置',
      ),
    ];
  }

  void _handleDestinationSelected(int index) {
    if (_currentIndex == index) {
      return;
    }

    setState(() {
      _currentIndex = index;
    });

    if (index == _settingsTabIndex) {
      ref.read(settingsCacheRefreshTriggerProvider.notifier).state++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final showUpdateBadge = ref.watch(showUpdateRedDotProvider);
    final destinations = _buildDestinations(showUpdateBadge);

    if (isLandscape) {
      // 横屏布局：使用 NavigationRail
      return Scaffold(
        body: Stack(
          children: [
            // 主内容区域
            Row(
              children: [
                // 侧边导航栏
                SafeArea(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: MediaQuery.of(context).size.height -
                            MediaQuery.of(context).padding.top -
                            MediaQuery.of(context).padding.bottom,
                      ),
                      child: IntrinsicHeight(
                        child: NavigationRail(
                          selectedIndex: _currentIndex,
                          onDestinationSelected: _handleDestinationSelected,
                          labelType: NavigationRailLabelType.selected,
                          destinations: destinations
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
                ),
                const VerticalDivider(thickness: 1, width: 1),
                // 页面内容
                Expanded(
                  child: Consumer(
                    builder: (context, ref, child) {
                      final authState = ref.watch(authProvider);
                      final isOfflineMode = authState.currentUser != null &&
                          !authState.isLoggedIn &&
                          authState.error != null;

                      return Padding(
                        padding: EdgeInsets.only(top: isOfflineMode ? 30 : 0),
                        child: SafeArea(
                          top: false,
                          child: Column(
                            children: [
                              // 主内容
                              Expanded(
                                child: PageStorage(
                                  bucket: _bucket,
                                  child: IndexedStack(
                                    index: _currentIndex,
                                    children:
                                        List.generate(_screens.length, (index) {
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
                                  final currentTrack =
                                      ref.watch(currentTrackProvider);
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
                      );
                    },
                  ),
                ),
              ],
            ),
            // 离线模式提示横幅（覆盖在顶部）
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Consumer(
                builder: (context, ref, child) {
                  final authState = ref.watch(authProvider);
                  final isOfflineMode = authState.currentUser != null &&
                      !authState.isLoggedIn &&
                      authState.error != null;

                  if (!isOfflineMode) {
                    return const SizedBox.shrink();
                  }

                  final topPadding = MediaQuery.of(context).padding.top;

                  return Container(
                    width: double.infinity,
                    padding: EdgeInsets.fromLTRB(12, topPadding + 4, 12, 4),
                    color: Colors.orange.shade800,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.cloud_off,
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            '离线模式：网络连接失败，仅可访问下载内容',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final notifier = ref.read(authProvider.notifier);
                            await notifier.retryConnection();
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            '重试',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    // 竖屏布局：使用 BottomNavigationBar
    return Scaffold(
      body: Stack(
        children: [
          // 主内容
          Consumer(
            builder: (context, ref, child) {
              final authState = ref.watch(authProvider);
              final isOfflineMode = authState.currentUser != null &&
                  !authState.isLoggedIn &&
                  authState.error != null;

              return Padding(
                padding: EdgeInsets.only(top: isOfflineMode ? 30 : 0),
                child: SafeArea(
                  top: false,
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
              );
            },
          ),
          // 离线模式提示横幅（覆盖在顶部）
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Consumer(
              builder: (context, ref, child) {
                final authState = ref.watch(authProvider);
                final isOfflineMode = authState.currentUser != null &&
                    !authState.isLoggedIn &&
                    authState.error != null;

                if (!isOfflineMode) {
                  return const SizedBox.shrink();
                }

                final topPadding = MediaQuery.of(context).padding.top;

                return Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(12, topPadding + 4, 12, 4),
                  color: Colors.orange.shade800,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.cloud_off,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          '离线模式：网络连接失败，仅可访问下载内容',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final notifier = ref.read(authProvider.notifier);
                          await notifier.retryConnection();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          '重试',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
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
          Builder(
            builder: (context) {
              final mediaQuery = MediaQuery.of(context);
              final bottomPadding = mediaQuery.padding.bottom;
              final isIOS = Platform.isIOS;

              Widget navBar = NavigationBar(
                height: 58,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                selectedIndex: _currentIndex,
                onDestinationSelected: _handleDestinationSelected,
                destinations: destinations,
              );

              if (isIOS) {
                navBar = MediaQuery.removePadding(
                  context: context,
                  removeBottom: true,
                  child: navBar,
                );
              }

              final navBottomPadding =
                  isIOS ? (bottomPadding > 0 ? 6.0 : 0.0) : bottomPadding;

              return Padding(
                padding: EdgeInsets.only(bottom: navBottomPadding),
                child: navBar,
              );
            },
          ),
        ],
      ),
    );
  }
}
