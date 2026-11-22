# Changelog

All notable changes to **Hedone** will be documented in this file.

## [1.0.0] - 2026-11-22

### Added
- **双源漫画聚合架构**：内置 JMComic3（动态 Host 解密、API 加解密、图片切片反混淆）与 E-Hentai / ExHentai（表里站切换、分类掩码、热门/订阅/排行、高级搜索与图片解析）双源仓库。
- **批量识别 JM 车牌号收藏**：新增 `JmIdExtractor` 与批量识别导入界面，支持从任意文本或 URL 自动提取并去重 JM ID，自动跳过日期、手机号和 E-Hentai 链接并支持批量加入收藏。
- **Prism UI & Material Design 3 界面重构**：
  - 引入基于 FlClash 的 `PrismNavigationDock` 悬浮胶囊导航栏、`PrismSidebar` 折叠侧边栏、`PrismSegmentedControl` 滑动分段器与 `PrismThemeCrossFade` 主题切换快照渐变；
  - 对齐 Material Design 3 规范（`md3_tokens.dart`），提供 5 套主题色预设、AMOLED 纯黑模式、3 档对比度及深浅色单按钮切换；
  - 全局内置 Adobe 思源黑体（`SourceHanSansCN` Regular / Medium / Bold），保留原版人物应用图标。
- **四模式阅读器与离线管理**：支持条漫、日漫右翻左、左翻右、双页并排阅读，内置章节下载队列、本地多收藏夹管理、阅读历史记录与 EhTagTranslation 中文词库。
- **云端收藏夹与排序**：
  - 支持展示 JMComic 云端 `folder_list` 收藏夹切换、排序切换（`收藏时间 mr` / `更新时间 mp`）及分页加载；
  - 支持解析并展示 E-Hentai / ExHentai 全部分组及 `favcat 0..9` 云端收藏夹与条数统计。

### Fixed
- **云端收藏自动同步与缓存**：进入书架「云端收藏」标签页时自动拉取并按账号与收藏夹缓存结果，切换页面不再要求每次手动同步；同时保留下拉刷新与手动同步按钮，并在账号或里站配置变更时自动失效缓存。
- **E-Hentai 论坛账密登录**：修复 Dio 开启 `followRedirects: true` 时丢失 302 重定向链中的 `Set-Cookie` 问题；登录流程现先请求登录页获取会话 Cookie，再以手动重定向循环收集每一跳的 `ipb_member_id` / `ipb_pass_hash`，随后探测 `sk` 与 `igneous`，并在触发 CAPTCHA 人机验证时给出明确提示与 Cookie 登录跳转入口（不再在缺失有效 Cookie 时误报登录成功）。
