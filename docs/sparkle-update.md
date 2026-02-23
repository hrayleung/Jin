# Sparkle Update Implementation

## 当前更新链路（已接入 Sparkle）
- 应用启动时：
  - `ContentView.task` 会调用 `updateManager.checkForUpdatesOnLaunchIfNeeded()`。
  - `SparkleUpdateManager` 使用 `SPUStandardUpdaterController` 发起后台检查（`checkForUpdatesInBackground()`）。
- 手动检查：
  - 设置页“Check for Updates”按钮触发 `SparkleUpdateManager.triggerManualCheck()`。
  - Sparkle 会弹出标准更新对话框（检测到更新时）。
- 预发布开关：
  - “Include pre-release versions” 映射到 `SPUUpdaterDelegate.allowedChannels` 的 `beta` 通道。

## 关键改动
- `Package.swift`
  - 新增依赖：`https://github.com/sparkle-project/Sparkle`
- `Sources/Networking/SparkleUpdateManager.swift`
  - 新建 `SparkleUpdateManager`
  - 负责 updater 初始化、自动检查开关、手动检查、预发布通道控制
- `Sources/UI/JinApp.swift`
  - 注入 `SparkleUpdateManager` 到主界面与设置页
  - 注册更新相关默认值
- `Sources/UI/ContentView.swift`
  - 移除旧的 GitHub API 版本检查逻辑与弹窗流程
  - 启动时走 Sparkle 后台检查
- `Sources/UI/UpdateSettingsView.swift`
  - 移除版本号对比/Release 列表/下载安装逻辑
  - 保留版本显示 + Sparkle 开关 + 手动检查
- `Packaging/Info.plist`
  - 新增 `SUFeedURL` 与 `SUScheduledCheckInterval`
- `Packaging/package.sh`
  - 增加 `Jin.zip` 产物，用于发布到 GitHub release

## GitHub Releases 发布流程（建议）
1. 在 CI/本地构建并打包：
   - `bash Packaging/package.sh`
   - 产物：`dist/Jin.zip`
2. 为该版本创建 GitHub Release，上传 `Jin.zip`
3. 生成/更新 appcast（Sparkle）
   - 使用 Sparkle 的 `generate_appcast` 生成 `appcast.xml`
   - 发布到你的静态站点，例如：
     - `https://hrayleung.github.io/Jin/appcast.xml`
4. 在 GitHub 仓库配置 Pages（或外部托管）提供该 `appcast.xml` 地址。

## 配置字段
- `Packaging/Info.plist`:
  - `SUFeedURL`: appcast 地址
  - `SUScheduledCheckInterval`: 秒数（当前为 86400）
- `AppPreferenceKeys`:
  - `updateAutoCheckOnLaunch`
  - `updateAllowPreRelease`

## 备注
- `SUFeedURL` 当前使用示例值，请确认为你的实际发布域名。
- 生产环境建议在 appcast 中开启签名并在 Info.plist 配置 `SUPublicEDKey`（可选但建议）。
