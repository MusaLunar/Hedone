<div align="center">
  <img src="assets/images/logo.png" alt="Hedone Logo" width="128" height="128" />
  <h1>Hedone</h1>
  <p>基于 Flutter 与 Material Design 3 构建的 JMComic3 &amp; E-Hentai/ExHentai 双源漫画阅读器</p>
  <p>
    <a href="LICENSE">AGPL-3.0 License</a> ·
    <a href="CHANGELOG.md">Changelog</a>
  </p>
</div>

---

## ✨ 主要特性

### 双源聚合与协议支持
- **JMComic3 源**：支持动态线路发现、AES/MD5 请求加解密、章节切片拼图反混淆（支持不同 `aid` 区间与 GIF 跳过），支持推荐页、分类浏览、排行及关键词搜索。
- **E-Hentai / ExHentai 源**：支持表里站切换、10 位分类掩码过滤（`f_cats`）、热门/订阅/排行榜与高级搜索、`showpage` 图片解析及 ExHentai 限流检测。
- **EH 标签中文翻译**：内置并支持更新 Mapaler 二进制标签词库（`EhTagTranslation`），在详情与搜索建议中展示双语标签。
- **批量识别 JM 车牌号**：内置文本剪贴/正则提取器（`JmIdExtractor`），可从大段文本或链接中自动识别并去重 JM 车牌号（自动过滤日期、电话、EH 链接），一键预览元数据并批量加入本地收藏。

### 账号、书架与云端收藏
- **多方式登录**：
  - JMComic 账号登录；
  - E-Hentai **论坛账号密码登录**（完整追踪重定向 `Set-Cookie` 与 `sk` / `igneous` 探测，自动识别人机验证提示）与 **Cookie 快捷导入**（支持剪贴板自动提取）。
- **本地与云端收藏**：
  - 本地多收藏夹管理，支持按源筛选；
  - **云端收藏自动加载与本地缓存**：进入云端收藏页自动同步一次并按账号与收藏夹缓存，切换标签页不重复同步，支持下拉刷新或手动同步；
  - **云端收藏夹切换与排序**：完整显示 JMComic 云端 `folder_list`（支持 `收藏时间` / `更新时间` 排序与分页）以及 E-Hentai 10 组 `favcat` 云端收藏夹与计数展示。
- **阅读进度与离线下载**：本地章节阅读历史自动记录（支持撤销删除）与章节离线缓存管理。

### 沉浸式阅读器
- 内置 4 种阅读模式：**条漫模式**、**日漫右翻左**、**左翻右**、**双页并排**。
- 支持阅读亮度调节与章节/页码快捷跳转。

### 界面与动效（Material Design 3 + Prism UI）
- **Prism UI 导航与动效**：参考 `FlClash` 引入悬浮液态玻璃胶囊导航栏（`PrismNavigationDock`）及桌面端可折叠侧边栏（`PrismSidebar`），支持在设置中切换；宽屏悬浮栏旁配有快捷深浅色切换球。
- **动态主题切换与视觉定制**：全局内置 **思源黑体（Source Han Sans CN）**，支持基于快照叠化的平滑深浅色切换动画（`PrismThemeCrossFade`）、5 套预设主题色（星夜紫 / 星光粉 / 深渊堇 / 翡冷翠 / 深海蓝）、AMOLED 纯黑背景以及 3 档 MD3 对比度调节。

---

## 🛠️ 开发与构建

### 环境要求
- Flutter SDK（当前工程 Dart SDK 约束为 `^3.13.5`）
- Windows：Visual Studio 2022（含桌面 C++ 开发工具链）与 Windows 10/11 SDK
- Android：Android SDK 与 JDK 17+

### 常用命令

```bash
# 安装依赖
flutter pub get

# 静态检查与测试
flutter analyze
flutter test -j 1

# 运行桌面或移动端调试版
flutter run -d windows
flutter run -d android

# 打包 Release 版本
flutter build windows --release
flutter build apk --release
```

---

## 🙏 致谢与参考项目

本项目的协议实现、交互设计与界面细节参考并学习了以下优秀开源项目（感谢各项目作者与贡献者）：

- [ComicSparks/jasmine](https://github.com/ComicSparks/jasmine) — JMComic 跨平台客户端设计与云端收藏夹交互参考
- [xiaojieonly/Ehviewer_CN_SXJ](https://github.com/xiaojieonly/Ehviewer_CN_SXJ) — E-Hentai/ExHentai 解析协议、收藏分类及论坛登录参考
- [Tom6814/JMComic3-APK-NO-Ads](https://github.com/Tom6814/JMComic3-APK-NO-Ads) — JMComic3 线路、签名及图像反混淆逻辑参考
- [delta-comic/delta-comic](https://github.com/delta-comic/delta-comic) — 多源漫画聚合客户端架构参考
- [chen08209/FlClash](https://github.com/chen08209/FlClash) — Prism UI 悬浮胶囊导航栏、折叠侧边栏与平滑主题过渡动效参考
- [lwhhz/Android-MD3-Knowledge](https://github.com/lwhhz/Android-MD3-Knowledge) — Material Design 3 色彩、排版、间距与对比度规范

---

## 📄 开源协议

本项目基于 [GNU Affero General Public License v3.0 (AGPL-3.0)](LICENSE) 开源。
