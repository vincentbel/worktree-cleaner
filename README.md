# Worktree Cleaner

一个使用 Swift 6 和 SwiftUI 开发的原生 macOS Git worktree 管理应用。

## 本地运行

要求：macOS 14 或更高版本，并安装支持 Swift 6 的 Xcode。

### 使用 Xcode

```bash
cd worktree-cleaner
open WorktreeCleaner.xcodeproj
```

在 Xcode 中选择 `WorktreeCleaner` Scheme 和 `My Mac` 运行目标，然后按 `⌘R`。
应用启动后点击“选择目录”，选择包含 Git 项目的基础目录。

### 使用命令行

```bash
cd worktree-cleaner

xcodebuild \
  -project WorktreeCleaner.xcodeproj \
  -scheme WorktreeCleaner \
  -configuration Debug \
  -derivedDataPath /tmp/worktree-cleaner-derived \
  CODE_SIGNING_ALLOWED=NO \
  build

open /tmp/worktree-cleaner-derived/Build/Products/Debug/WorktreeCleaner.app
```

如果出现 `IDESimulatorFoundation` 或 `DVTDownloads` 相关错误，请先打开 Xcode
完成首次启动组件安装。问题仍然存在时，需要更新或重装与当前 macOS 版本匹配的
Xcode。

## 运行测试

```bash
swift test --package-path Packages/WorktreeCore
```

更多开发和验证命令参见 [docs/development.md](docs/development.md)。
