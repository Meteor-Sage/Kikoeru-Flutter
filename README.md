<div align="center">
  <img src="assets/icons/app_icon_black.png" alt="KikoFlu" width="120" height="120">

  # KikoFlu

  **一个跨平台同人音声客户端，基于Kikoeru**

  [![Flutter](https://img.shields.io/badge/Flutter-3.0+-02569B?logo=flutter)](https://flutter.dev)
  [![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20macOS-lightgrey)](https://github.com/Meteor-Sage/Kikoeru-Flutter)
  [![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>


<div align="center">
  <img src="screenshots/8.png" width="900" alt="">
</div>


</div>



## 特性

### 🎵 媒体
- 自动缓存机制
- 后台播放
- 倍速播放
- 自动歌词
- 单曲循环、列表循环、随机播放
- 支持整个作品或选择性下载
- 多媒体支持：音频、视频、文本、图片、pdf...
- 字幕导入、编辑、调轴、翻译、台词自动载入
- 支持保存目录修改，跨硬盘拷贝

### 🎨 界面
- 全平台支持
- 遵循Material Design 3设计规范
- 支持横屏模式
- 优化的页面转场和交互反馈
- 完美适配明暗主题
- 标题，文件目录，文本文件翻译
- 防社死模式
- 评分系统

### 🔍 搜索
- 强大的高级搜索机制，支持多标签/排除标签搜索
- 多维度筛选作品（标签、评分、发售日期等）
- 完整展示作品信息

### ⚙️ 设置
- 多账户支持
- 支持自定义服务器地址，可测试连接延迟
- 自定义缓存大小限制和清理策略
- 主题模式、配色方案自由选择
- 大量自定义UI，可简洁可详细
- 更新检查


---

## [Releases](https://github.com/Meteor-Sage/Kikoeru-Flutter/releases)

---

## 源码构建

- Flutter SDK 3.0 或更高版本
- Dart SDK 3.0 或更高版本
- VS Code

```bash
git clone https://github.com/Meteor-Sage/Kikoeru-Flutter.git
cd Kikoeru-Flutter
```

```bash
flutter pub get
```

### Android
```bash
flutter build apk --release

flutter build apk --release --split-per-abi
```

### Windows
```bash
flutter build windows --release

flutter pub run msix:create
```

### iOS
```bash
./build_ios_xcode.sh
```

### macOS
```bash
./build_macos.sh
```


## 开源协议

[MIT License](LICENSE)

---

## 相关

- [Kikoeru](https://github.com/kikoeru-project) - 提供后端服务

---

## 联系方式

- **项目地址**: [GitHub](https://github.com/Meteor-Sage/Kikoeru-Flutter)
- **问题反馈**: [Issues](https://github.com/Meteor-Sage/Kikoeru-Flutter/issues) [Telegram](https://t.me/+PrkiN-pZrXs4ZTU1)

---

<div align="center">

  **如果这个项目对你有帮助，请给个 ⭐ Star 支持一下！**

</div>
