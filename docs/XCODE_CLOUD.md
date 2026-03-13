# Xcode Cloud 配置说明

本文档用于在 `PiliPlus` 项目中启用 Xcode Cloud 并对接 TestFlight。

## 已在仓库内准备的内容

- `ios/ci_scripts/ci_post_clone.sh`
  - 自动安装/准备 Flutter SDK（优先读取 `.fvmrc` 版本）
  - 执行 `flutter pub get`
  - 执行 `pod install`
- `ios/ci_scripts/ci_pre_xcodebuild.sh`
  - 清理会污染 iOS 编译的环境变量（`CPATH`、`LIBRARY_PATH`、`SDKROOT`）
  - 写入 `pili_release.json`
  - 将 `pili.name/pili.code/pili.hash/pili.time` 注入 `DART_DEFINES`

## App Store Connect 前置条件

1. 目标 App 已在 App Store Connect 创建
2. Bundle Identifier 与 Xcode 工程一致
3. Apple Developer Team、证书与签名配置可用
4. 仓库已推送到 GitHub，且 Actions/Cloud 权限开启

## 在 Xcode 中创建 Workflow

1. 打开 `ios/Runner.xcworkspace`
2. 进入 `Product -> Xcode Cloud -> Create Workflow...`
3. 选择 GitHub 仓库与分支（建议 `main`）
4. 推荐先创建两个工作流：
   - `CI-PR`：执行 Build/Test，不分发
   - `Release-TestFlight`：手动触发，执行 Archive 并分发到 TestFlight
5. 在 `Release-TestFlight` 工作流中设置：
   - Action: `Archive`
   - Distribution: `TestFlight (Internal Testing)`
   - Trigger: `Manual`（先手动，稳定后再改自动）

## 推荐触发策略

- `CI-PR`：Pull Request 自动触发
- `Release-TestFlight`：手动触发（避免误发）

## 常见问题

### 1. 本地不提示最新，Cloud 提示有更新（或相反）

项目更新检查依赖 `pili.time`。本仓库已在 `ci_pre_xcodebuild.sh` 自动注入构建时间，避免默认值导致的误判。

### 2. Upload Symbols Failed（dSYM 警告）

若仅为三方预编译框架缺失 dSYM，通常不会阻塞 TestFlight 分发，但会影响相关崩溃的符号化质量。

### 3. 模拟器构建失败但真机构建正常

部分三方库仅影响模拟器架构，TestFlight 走真机归档链路，可先以 Archive 结果为准。

