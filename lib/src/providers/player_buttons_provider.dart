import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 播放器按钮类型
enum PlayerButtonType {
  seekBackward('后退10秒', 'seek_backward'),
  seekForward('前进10秒', 'seek_forward'),
  sleepTimer('定时器', 'sleep_timer'),
  mark('标记作品', 'mark'),
  volume('音量控制', 'volume'),
  speed('播放速度', 'speed'),
  repeat('循环模式', 'repeat'),
  detail('查看详情', 'detail'),
  subtitleAdjustment('字幕轴调整', 'subtitle_adjustment');

  final String label;
  final String key;
  const PlayerButtonType(this.label, this.key);
}

/// 播放器按钮配置状态
class PlayerButtonsConfig {
  final List<PlayerButtonType> buttonOrder;

  const PlayerButtonsConfig({
    required this.buttonOrder,
  });

  /// 默认配置 - 移动端
  static const defaultMobile = PlayerButtonsConfig(
    buttonOrder: [
      PlayerButtonType.seekBackward,
      PlayerButtonType.seekForward,
      PlayerButtonType.sleepTimer,
      PlayerButtonType.mark,
      PlayerButtonType.speed,
      PlayerButtonType.repeat,
      PlayerButtonType.subtitleAdjustment,
      PlayerButtonType.detail,
    ],
  );

  /// 默认配置 - 桌面端
  static const defaultDesktop = PlayerButtonsConfig(
    buttonOrder: [
      PlayerButtonType.seekBackward,
      PlayerButtonType.seekForward,
      PlayerButtonType.sleepTimer,
      PlayerButtonType.mark,
      PlayerButtonType.volume,
      PlayerButtonType.speed,
      PlayerButtonType.repeat,
      PlayerButtonType.subtitleAdjustment,
      PlayerButtonType.detail,
    ],
  );

  /// 获取显示的按钮（前4个或5个）
  List<PlayerButtonType> getVisibleButtons(bool isDesktop) {
    final maxVisible = isDesktop ? 5 : 4;
    return buttonOrder.take(maxVisible).toList();
  }

  /// 获取更多菜单中的按钮
  List<PlayerButtonType> getMoreButtons(bool isDesktop) {
    final maxVisible = isDesktop ? 5 : 4;
    return buttonOrder.skip(maxVisible).toList();
  }

  /// 从JSON加载
  factory PlayerButtonsConfig.fromJson(Map<String, dynamic> json) {
    final orderKeys = (json['buttonOrder'] as List<dynamic>).cast<String>();
    final buttonOrder = orderKeys
        .map((key) => PlayerButtonType.values.firstWhere(
              (type) => type.key == key,
              orElse: () => PlayerButtonType.seekBackward,
            ))
        .toList();
    return PlayerButtonsConfig(buttonOrder: buttonOrder);
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'buttonOrder': buttonOrder.map((type) => type.key).toList(),
    };
  }

  PlayerButtonsConfig copyWith({
    List<PlayerButtonType>? buttonOrder,
  }) {
    return PlayerButtonsConfig(
      buttonOrder: buttonOrder ?? this.buttonOrder,
    );
  }
}

/// 播放器按钮配置控制器
class PlayerButtonsConfigController extends StateNotifier<PlayerButtonsConfig> {
  static const String _prefKey = 'player_buttons_config';
  static const String _prefKeyDesktop = 'player_buttons_config_desktop';

  final bool _isDesktop;

  PlayerButtonsConfigController(this._isDesktop)
      : super(_isDesktop
            ? PlayerButtonsConfig.defaultDesktop
            : PlayerButtonsConfig.defaultMobile) {
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _isDesktop ? _prefKeyDesktop : _prefKey;
      final jsonString = prefs.getString(key);

      if (jsonString != null) {
        final savedOrder = (jsonString.split(','))
            .map((key) => PlayerButtonType.values.firstWhere(
                  (type) => type.key == key,
                  orElse: () => PlayerButtonType.seekBackward,
                ))
            .toList();

        // 获取默认配置，用于合并新按钮
        final defaultOrder = _isDesktop
            ? PlayerButtonsConfig.defaultDesktop.buttonOrder
            : PlayerButtonsConfig.defaultMobile.buttonOrder;

        // 找出新添加的按钮（在默认配置中存在但保存的配置中不存在）
        final newButtons = defaultOrder
            .where((button) => !savedOrder.contains(button))
            .toList();

        // 将新按钮添加到末尾
        final mergedOrder = [...savedOrder, ...newButtons];

        state = PlayerButtonsConfig(buttonOrder: mergedOrder);

        // 如果有新按钮被添加，保存更新后的配置
        if (newButtons.isNotEmpty) {
          await _saveConfig();
        }
      }
    } catch (e) {
      // 如果加载失败，使用默认配置
      state = _isDesktop
          ? PlayerButtonsConfig.defaultDesktop
          : PlayerButtonsConfig.defaultMobile;
    }
  }

  Future<void> updateButtonOrder(List<PlayerButtonType> newOrder) async {
    state = state.copyWith(buttonOrder: newOrder);
    await _saveConfig();
  }

  Future<void> _saveConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _isDesktop ? _prefKeyDesktop : _prefKey;
      final orderString = state.buttonOrder.map((type) => type.key).join(',');
      await prefs.setString(key, orderString);
    } catch (e) {
      // 保存失败时静默处理
    }
  }

  Future<void> resetToDefault() async {
    state = _isDesktop
        ? PlayerButtonsConfig.defaultDesktop
        : PlayerButtonsConfig.defaultMobile;
    await _saveConfig();
  }
}

/// 移动端按钮配置Provider
final playerButtonsConfigMobileProvider =
    StateNotifierProvider<PlayerButtonsConfigController, PlayerButtonsConfig>(
  (ref) => PlayerButtonsConfigController(false),
);

/// 桌面端按钮配置Provider
final playerButtonsConfigDesktopProvider =
    StateNotifierProvider<PlayerButtonsConfigController, PlayerButtonsConfig>(
  (ref) => PlayerButtonsConfigController(true),
);
