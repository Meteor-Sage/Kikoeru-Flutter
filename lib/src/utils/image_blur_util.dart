import 'dart:ui' as ui;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// 图片模糊处理工具类
class ImageBlurUtil {
  /// 对网络图片或本地图片应用高强度高斯模糊并保存到临时文件
  /// 返回模糊后的图片文件路径（file:// 协议）
  static Future<String?> blurNetworkImageToFile(String imageUrl) async {
    try {
      // 生成缓存文件名（基于URL的hash）
      final urlHash = md5.convert(utf8.encode(imageUrl)).toString();
      final tempDir = await getTemporaryDirectory();
      final blurredFile = File('${tempDir.path}/blurred_$urlHash.png');

      // 如果已经存在模糊后的文件，直接返回
      if (await blurredFile.exists()) {
        return 'file://${blurredFile.path}';
      }

      Uint8List imageData;

      // 判断是本地文件还是网络URL
      if (imageUrl.startsWith('file://')) {
        // 本地文件
        final localPath = imageUrl.substring(7); // 移除 'file://' 前缀
        final localFile = File(localPath);
        if (!await localFile.exists()) {
          debugPrint('本地图片文件不存在: $localPath');
          return null;
        }
        imageData = await localFile.readAsBytes();
      } else {
        // 网络URL
        final response = await http.get(Uri.parse(imageUrl));
        if (response.statusCode != 200) {
          debugPrint('下载图片失败: ${response.statusCode}');
          return null;
        }
        imageData = response.bodyBytes;
      }

      // 解码图片
      final ui.Codec codec = await ui.instantiateImageCodec(imageData);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image image = frameInfo.image;

      // 应用极高强度模糊 (sigma = 100)
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);

      // 创建高斯模糊滤镜
      final Paint paint = Paint()
        ..imageFilter = ui.ImageFilter.blur(sigmaX: 100.0, sigmaY: 100.0);

      // 绘制模糊图片
      canvas.drawImage(image, Offset.zero, paint);

      // 转换为图片
      final ui.Picture picture = recorder.endRecording();
      final ui.Image blurredImage = await picture.toImage(
        image.width,
        image.height,
      );

      // 转换为PNG字节数据
      final ByteData? byteData = await blurredImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData == null) {
        return null;
      }

      final Uint8List pngBytes = byteData.buffer.asUint8List();

      // 保存到临时文件
      await blurredFile.writeAsBytes(pngBytes);

      return 'file://${blurredFile.path}';
    } catch (e) {
      debugPrint('模糊图片失败: $e');
      return null;
    }
  }
}
