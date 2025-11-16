import 'package:flutter/material.dart';
import '../models/work.dart';

/// 文件图标工具类
/// 用于根据文件类型返回对应的图标和颜色
class FileIconUtils {
  FileIconUtils._();

  /// 获取文件图标（通过文件名）
  static IconData getFileIconByName(String fileName) {
    final title = fileName.toLowerCase();

    // 视频文件
    if (_isVideoFile(title)) {
      return Icons.video_library;
    }
    // 图片文件
    else if (_isImageFile(title)) {
      return Icons.image;
    }
    // 文本文件
    else if (_isTextFile(title)) {
      return Icons.text_snippet;
    }
    // PDF 文件
    else if (_isPdfFile(title)) {
      return Icons.picture_as_pdf;
    }
    // 音频文件（默认）
    else {
      return Icons.audiotrack;
    }
  }

  /// 获取文件图标颜色（通过文件名）
  static Color getFileIconColorByName(String fileName) {
    final title = fileName.toLowerCase();

    // 视频文件
    if (_isVideoFile(title)) {
      return Colors.purple;
    }
    // 图片文件
    else if (_isImageFile(title)) {
      return Colors.blue;
    }
    // 文本文件
    else if (_isTextFile(title)) {
      return Colors.grey;
    }
    // PDF 文件
    else if (_isPdfFile(title)) {
      return Colors.red;
    }
    // 音频文件（默认）
    else {
      return Colors.green;
    }
  }

  /// 获取文件图标（通过 AudioFile 对象）
  static IconData getFileIcon(AudioFile file) {
    final type = file.type;
    final title = file.title.toLowerCase();

    if (type == 'folder') {
      return Icons.folder;
    } else if (type == 'audio' || type == 'file') {
      if (_isVideoFile(title)) {
        return Icons.video_library;
      } else if (type == 'image' || _isImageFile(title)) {
        return Icons.image;
      } else if (type == 'text' || _isTextFile(title)) {
        return Icons.text_snippet;
      } else if (type == 'pdf' || _isPdfFile(title)) {
        return Icons.picture_as_pdf;
      }
      return Icons.audiotrack;
    } else {
      return Icons.insert_drive_file;
    }
  }

  /// 获取文件图标颜色（通过 AudioFile 对象）
  static Color getFileIconColor(AudioFile file) {
    final type = file.type;
    final title = file.title.toLowerCase();

    if (type == 'folder') {
      return Colors.amber;
    } else if (type == 'audio' || type == 'file') {
      if (_isVideoFile(title)) {
        return Colors.purple;
      } else if (type == 'image' || _isImageFile(title)) {
        return Colors.blue;
      } else if (type == 'text' || _isTextFile(title)) {
        return Colors.grey;
      } else if (type == 'pdf' || _isPdfFile(title)) {
        return Colors.red;
      }
      return Colors.green;
    } else {
      return Colors.grey;
    }
  }

  /// 获取文件图标（通过 Map 对象 - 用于 file_explorer_widget）
  static IconData getFileIconFromMap(Map<String, dynamic> file) {
    final type = file['type'] ?? '';
    final title = (file['title'] ?? file['name'] ?? '').toLowerCase();

    if (type == 'folder') {
      return Icons.folder;
    } else if (type == 'audio') {
      if (_isVideoFile(title)) {
        return Icons.video_library;
      }
      return Icons.audiotrack;
    } else if (type == 'image' || _isImageFile(title)) {
      return Icons.image;
    } else if (type == 'text' || _isTextFile(title)) {
      return Icons.text_snippet;
    } else if (type == 'pdf' || _isPdfFile(title)) {
      return Icons.picture_as_pdf;
    } else {
      return Icons.insert_drive_file;
    }
  }

  /// 获取文件图标颜色（通过 Map 对象 - 用于 file_explorer_widget）
  static Color getFileIconColorFromMap(Map<String, dynamic> file) {
    final type = file['type'] ?? '';
    final title = (file['title'] ?? file['name'] ?? '').toLowerCase();

    if (type == 'folder') {
      return Colors.amber;
    } else if (type == 'audio') {
      if (_isVideoFile(title)) {
        return Colors.purple;
      }
      return Colors.green;
    } else if (type == 'image' || _isImageFile(title)) {
      return Colors.blue;
    } else if (type == 'text' || _isTextFile(title)) {
      return Colors.grey;
    } else if (type == 'pdf' || _isPdfFile(title)) {
      return Colors.red;
    } else {
      return Colors.grey;
    }
  }

  // ========== 文件类型判断方法 ==========

  /// 判断是否是视频文件
  static bool _isVideoFile(String title) {
    return title.endsWith('.mp4') ||
        title.endsWith('.mkv') ||
        title.endsWith('.avi') ||
        title.endsWith('.mov') ||
        title.endsWith('.wmv') ||
        title.endsWith('.flv') ||
        title.endsWith('.webm') ||
        title.endsWith('.m4v');
  }

  /// 判断是否是图片文件
  static bool _isImageFile(String title) {
    return title.endsWith('.jpg') ||
        title.endsWith('.jpeg') ||
        title.endsWith('.png') ||
        title.endsWith('.gif') ||
        title.endsWith('.bmp') ||
        title.endsWith('.webp');
  }

  /// 判断是否是文本文件
  static bool _isTextFile(String title) {
    return title.endsWith('.txt') ||
        title.endsWith('.vtt') ||
        title.endsWith('.srt') ||
        title.endsWith('.lrc') ||
        title.endsWith('.md') ||
        title.endsWith('.log') ||
        title.endsWith('.json') ||
        title.endsWith('.xml');
  }

  /// 判断是否是 PDF 文件
  static bool _isPdfFile(String title) {
    return title.endsWith('.pdf');
  }

  /// 判断是否是音频文件
  static bool _isAudioFile(String title) {
    return title.endsWith('.mp3') ||
        title.endsWith('.wav') ||
        title.endsWith('.flac') ||
        title.endsWith('.m4a') ||
        title.endsWith('.aac') ||
        title.endsWith('.ogg') ||
        title.endsWith('.wma') ||
        title.endsWith('.opus');
  }

  /// 判断是否是字幕文件
  static bool isLyricFile(String title) {
    final lowerTitle = title.toLowerCase();
    return lowerTitle.endsWith('.vtt') ||
        lowerTitle.endsWith('.srt') ||
        lowerTitle.endsWith('.lrc') ||
        lowerTitle.endsWith('.txt');
  }

  /// 判断是否是图片文件（公开方法 - 用于 file_explorer_widget）
  static bool isImageFile(Map<String, dynamic> file) {
    final type = file['type'] ?? '';
    final title = (file['title'] ?? file['name'] ?? '').toLowerCase();
    return type == 'image' || _isImageFile(title);
  }

  /// 判断是否是文本文件（公开方法 - 用于 file_explorer_widget）
  static bool isTextFile(Map<String, dynamic> file) {
    final type = file['type'] ?? '';
    final title = (file['title'] ?? file['name'] ?? '').toLowerCase();
    return type == 'text' || _isTextFile(title);
  }

  /// 判断是否是 PDF 文件（公开方法 - 用于 file_explorer_widget）
  static bool isPdfFile(Map<String, dynamic> file) {
    final type = file['type'] ?? '';
    final title = (file['title'] ?? file['name'] ?? '').toLowerCase();
    return type == 'pdf' || _isPdfFile(title);
  }

  /// 判断是否是视频文件（公开方法 - 用于 file_explorer_widget）
  static bool isVideoFile(Map<String, dynamic> file) {
    final title = (file['title'] ?? file['name'] ?? '').toLowerCase();
    return _isVideoFile(title);
  }

  /// 判断是否是音频文件（公开方法 - 用于 offline_file_explorer_widget）
  static bool isAudioFile(Map<String, dynamic> file) {
    final type = file['type'] ?? '';
    final title = (file['title'] ?? file['name'] ?? '').toLowerCase();
    final isAudio = type == 'audio' || _isAudioFile(title);
    return isAudio;
  }
}
