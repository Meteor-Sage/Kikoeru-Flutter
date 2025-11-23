import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:desktop_multi_window/desktop_multi_window.dart';

/// 悬浮歌词服务
/// 负责管理桌面悬浮窗显示和歌词更新
class FloatingLyricService {
  static const _platform = MethodChannel('com.kikoeru.flutter/floating_lyric');

  static FloatingLyricService? _instance;
  String? _windowId;
  String? _lastText;
  
  final _onCloseController = StreamController<void>.broadcast();
  Stream<void> get onClose => _onCloseController.stream;

  FloatingLyricService._() {
    _platform.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onClose':
        _onCloseController.add(null);
        break;
    }
  }

  static FloatingLyricService get instance {
    _instance ??= FloatingLyricService._();
    return _instance!;
  }

  /// 检查是否支持悬浮窗
  bool get isSupported =>
      Platform.isAndroid ||
      Platform.isWindows ||
      Platform.isMacOS ||
      Platform.isIOS;

  /// 显示悬浮窗
  /// [text] 要显示的文本内容
  /// [style] 初始样式参数
  Future<bool> show(String text, {Map<String, dynamic>? style}) async {
    if (!isSupported) {
      print('[FloatingLyric] 当前平台不支持悬浮窗');
      return false;
    }

    if (Platform.isWindows) {
      try {
        if (_windowId != null) {
          final result = await updateText(text);
          if (result) {
            // 如果更新成功，且有样式参数，也更新样式
            if (style != null) {
              await updateStyle(
                fontSize: style['fontSize'],
                textColor: style['textColor'],
                backgroundColor: style['backgroundColor'],
                cornerRadius: style['cornerRadius'],
                paddingHorizontal: style['paddingHorizontal'],
                paddingVertical: style['paddingVertical'],
              );
            }
            return true;
          }
          // 如果更新失败，说明窗口可能已关闭，重置ID并重新创建
          _windowId = null;
        }

        final Map<String, dynamic> args = {'text': text};
        if (style != null) {
          args.addAll(style);
        }

        final controller = await WindowController.create(
          WindowConfiguration(
            arguments: jsonEncode(args),
          ),
        );
        _windowId = controller.windowId;
        await controller.show();
        return true;
      } catch (e) {
        print('[FloatingLyric] Desktop显示悬浮窗失败: $e');
        return false;
      }
    }

    try {
      final Map<String, dynamic> args = {'text': text};
      if (style != null) {
        args.addAll(style);
      }
      final result = await _platform.invokeMethod('show', args);
      print('[FloatingLyric] 显示悬浮窗: $text');
      return result == true;
    } catch (e) {
      print('[FloatingLyric] 显示悬浮窗失败: $e');
      return false;
    }
  }

  /// 隐藏悬浮窗
  Future<bool> hide() async {
    if (!isSupported) {
      return false;
    }

    if (Platform.isWindows) {
      if (_windowId != null) {
        try {
          final controller = WindowController.fromWindowId(_windowId!);
          await controller.invokeMethod('close');
        } catch (e) {
          print('[FloatingLyric] Windows隐藏悬浮窗失败: $e');
        }
        _windowId = null;
        return true;
      }
      return false;
    }

    try {
      final result = await _platform.invokeMethod('hide');
      print('[FloatingLyric] 隐藏悬浮窗');
      return result == true;
    } catch (e) {
      print('[FloatingLyric] 隐藏悬浮窗失败: $e');
      return false;
    }
  }

  /// 更新悬浮窗文本
  /// [text] 新的文本内容
  Future<bool> updateText(String text) async {
    if (!isSupported) {
      return false;
    }

    // 去重检查，避免频繁调用 MethodChannel
    if (text == _lastText) {
      return true;
    }
    _lastText = text;

    if (Platform.isWindows) {
      if (_windowId != null) {
        try {
          // print('[FloatingLyric] Updating text for window $_windowId: $text');
          final controller = WindowController.fromWindowId(_windowId!);
          await controller.invokeMethod('updateText', {
            'text': text,
          });
          return true;
        } catch (e) {
          print('[FloatingLyric] Windows更新文本失败: $e');
          // Do not reset _windowId here, as failure might be temporary (e.g. window initializing)
          // If window is truly closed, hide() will handle the cleanup when user toggles off.
          return false;
        }
      }
      return false;
    }

    try {
      final result = await _platform.invokeMethod('updateText', {
        'text': text,
      });
      return result == true;
    } catch (e) {
      print('[FloatingLyric] 更新文本失败: $e');
      return false;
    }
  }

  /// 检查是否有悬浮窗权限
  Future<bool> hasPermission() async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isIOS) return true;
    if (!isSupported) {
      return false;
    }

    try {
      final result = await _platform.invokeMethod('hasPermission');
      return result == true;
    } catch (e) {
      print('[FloatingLyric] 检查权限失败: $e');
      return false;
    }
  }

  /// 请求悬浮窗权限
  Future<bool> requestPermission() async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isIOS) return true;
    if (!isSupported) {
      return false;
    }

    try {
      final result = await _platform.invokeMethod('requestPermission');
      print('[FloatingLyric] 请求权限结果: $result');
      return result == true;
    } catch (e) {
      print('[FloatingLyric] 请求权限失败: $e');
      return false;
    }
  }

  /// 更新悬浮窗样式
  /// [fontSize] 字体大小
  /// [textColor] 文字颜色（ARGB格式）
  /// [backgroundColor] 背景颜色（ARGB格式）
  /// [cornerRadius] 圆角半径
  /// [paddingHorizontal] 水平内边距
  /// [paddingVertical] 垂直内边距
  Future<bool> updateStyle({
    double? fontSize,
    int? textColor,
    int? backgroundColor,
    double? cornerRadius,
    double? paddingHorizontal,
    double? paddingVertical,
  }) async {
    if (!isSupported) {
      return false;
    }

    final params = <String, dynamic>{};
    if (fontSize != null) params['fontSize'] = fontSize;
    if (textColor != null) params['textColor'] = textColor;
    if (backgroundColor != null) params['backgroundColor'] = backgroundColor;
    if (cornerRadius != null) params['cornerRadius'] = cornerRadius;
    if (paddingHorizontal != null)
      params['paddingHorizontal'] = paddingHorizontal;
    if (paddingVertical != null) params['paddingVertical'] = paddingVertical;

    if (Platform.isWindows) {
      if (_windowId != null) {
        try {
          final controller = WindowController.fromWindowId(_windowId!);
          await controller.invokeMethod('updateStyle', params);
          return true;
        } catch (e) {
          print('[FloatingLyric] Windows更新样式失败: $e');
          return false;
        }
      }
      return false;
    }

    try {
      final result = await _platform.invokeMethod('updateStyle', params);
      print('[FloatingLyric] 更新样式成功');
      return result == true;
    } catch (e) {
      print('[FloatingLyric] 更新样式失败: $e');
      return false;
    }
  }
}
