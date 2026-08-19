import SwiftUI
import UniformTypeIdentifiers
import WorktreeCore

struct ContentView: View {
  @State private var model = AppState()
  @State private var isChoosingDirectory = false
  @State private var pendingRemoval: GitWorktree?

  var body: some View {
    NavigationSplitView {
      List(model.repositories, selection: repositorySelection) { repository in
        RepositoryRow(repository: repository)
          .tag(repository.id)
      }
      .navigationTitle("项目")
      .overlay {
        if model.repositories.isEmpty, model.isScanning {
          ProgressView("正在扫描 Git 项目…")
        } else if model.repositories.isEmpty, model.baseDirectoryURL != nil {
          ContentUnavailableView(
            "没有找到 Git 项目",
            systemImage: "folder.badge.questionmark",
            description: Text("请选择其他基础目录，或确认目录中包含 Git 仓库。")
          )
        }
      }
      .safeAreaInset(edge: .bottom) {
        if let baseDirectoryURL = model.baseDirectoryURL {
          Text(baseDirectoryURL.path)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.bar)
        }
      }
    } detail: {
      detail
    }
    .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 380)
    .toolbar {
      ToolbarItemGroup {
        if model.isScanning || model.isLoadingSnapshot || model.isMeasuringDiskUsage {
          ProgressView()
            .controlSize(.small)
        }

        Button("选择目录", systemImage: "folder.badge.plus") {
          isChoosingDirectory = true
        }

        Button("刷新", systemImage: "arrow.clockwise") {
          Task { await model.scan() }
        }
        .disabled(model.baseDirectoryURL == nil || model.isScanning)
      }
    }
    .fileImporter(
      isPresented: $isChoosingDirectory,
      allowedContentTypes: [.folder],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else {
        if case .failure(let error) = result {
          model.errorMessage = error.localizedDescription
        }
        return
      }
      Task { await model.chooseDirectory(url) }
    }
    .alert(
      "操作失败",
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: { if !$0 { model.errorMessage = nil } }
      )
    ) {
      Button("好", role: .cancel) {}
    } message: {
      Text(model.errorMessage ?? "未知错误")
    }
    .alert(
      "操作完成",
      isPresented: Binding(
        get: { model.successMessage != nil },
        set: { if !$0 { model.successMessage = nil } }
      )
    ) {
      Button("好", role: .cancel) {}
    } message: {
      Text(model.successMessage ?? "操作已完成。")
    }
    .alert(
      removalTitle,
      isPresented: Binding(
        get: { pendingRemoval != nil },
        set: { if !$0 { pendingRemoval = nil } }
      ),
      presenting: pendingRemoval
    ) { worktree in
      Button(removalButtonTitle(for: worktree), role: .destructive) {
        pendingRemoval = nil
        Task { await model.remove(worktree) }
      }
      Button("取消", role: .cancel) {
        pendingRemoval = nil
      }
    } message: { worktree in
      Text(removalMessage(for: worktree))
    }
    .task {
      await model.restoreSelectedDirectory()
    }
  }

  private var repositorySelection: Binding<GitRepository.ID?> {
    Binding(
      get: { model.selectedRepositoryID },
      set: { repositoryID in
        guard model.selectedRepositoryID != repositoryID else { return }
        model.selectedRepositoryID = repositoryID
        Task { await model.loadSelectedRepository() }
      }
    )
  }

  @ViewBuilder
  private var detail: some View {
    if model.baseDirectoryURL == nil {
      ContentUnavailableView {
        Label("选择基础目录", systemImage: "folder.badge.plus")
      } description: {
        Text("Worktree Manager 会递归发现其中的 Git 项目。")
      } actions: {
        Button("选择目录") {
          isChoosingDirectory = true
        }
        .buttonStyle(.borderedProminent)
      }
    } else if let snapshot = model.snapshot,
      snapshot.repository.id == model.selectedRepositoryID
    {
      WorktreeTable(
        snapshot: snapshot,
        worktreeAllocatedBytes: model.worktreeAllocatedBytes,
        sharedGitAllocatedBytes: model.sharedGitAllocatedBytes,
        removingWorktreeID: model.removingWorktreeID,
        onMessage: { model.successMessage = $0 },
        onError: { model.errorMessage = $0 },
        onRemove: { pendingRemoval = $0 }
      )
    } else if model.isScanning || model.isLoadingSnapshot {
      ProgressView("正在读取 Git 状态…")
    } else {
      ContentUnavailableView(
        "选择一个项目",
        systemImage: "point.3.connected.trianglepath.dotted"
      )
    }
  }

  private var removalTitle: String {
    guard let pendingRemoval else { return "确认删除这个 worktree？" }
    switch pendingRemoval.cleanupRecommendation.removalKind {
    case .unmerged(let target):
      return "尚未合入 \(target)，仍要删除？"
    default:
      return "确认删除这个 worktree？"
    }
  }

  private func removalButtonTitle(for worktree: GitWorktree) -> String {
    switch worktree.cleanupRecommendation.removalKind {
    case .unmerged:
      "仍然删除未合入的 worktree"
    default:
      "永久删除 worktree"
    }
  }

  private func removalMessage(for worktree: GitWorktree) -> String {
    switch worktree.cleanupRecommendation.removalKind {
    case .unmerged(let target):
      let recoveryMessage =
        worktree.branch.map {
          "Git 分支 \($0) 会保留。"
        } ?? "当前为 Detached HEAD；删除后提交可能难以找回，请先记录提交 \(worktree.head)。"
      return
        "这个 worktree 的提交尚未合入 \(target)。目录删除后无法撤销。\(recoveryMessage)执行前会再次检查工作区是否干净。\n\n\(worktree.path.path)"
    default:
      return
        "将通过 Git 删除这个目录。此操作不可撤销，但不会删除分支。执行前会再次检查 Git 状态。\n\n\(worktree.path.path)"
    }
  }
}

private struct RepositoryRow: View {
  let repository: GitRepository

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(repository.name)
        .fontWeight(.medium)
      Text(repository.workingTreeURL.path)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .padding(.vertical, 3)
  }
}

private struct WorktreeTable: View {
  let snapshot: RepositorySnapshot
  let worktreeAllocatedBytes: [URL: Int64]
  let sharedGitAllocatedBytes: Int64?
  let removingWorktreeID: GitWorktree.ID?
  let onMessage: (String) -> Void
  let onError: (String) -> Void
  let onRemove: (GitWorktree) -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("\(snapshot.worktrees.count) 个 worktree")
        Spacer()
        if let sharedGitAllocatedBytes {
          Label(
            "共享 Git 数据 \(formattedBytes(sharedGitAllocatedBytes))",
            systemImage: "externaldrive"
          )
          .foregroundStyle(.secondary)
        } else {
          Label("正在计算共享 Git 数据…", systemImage: "externaldrive")
            .foregroundStyle(.secondary)
        }
      }
      .font(.callout)
      .padding(.horizontal)
      .padding(.vertical, 10)

      Divider()

      GeometryReader { geometry in
        ScrollView(.vertical) {
          HStack(alignment: .top, spacing: 0) {
            ScrollView(.horizontal) {
              VStack(spacing: 0) {
                WorktreeGridHeader()
                ForEach(Array(snapshot.worktrees.enumerated()), id: \.element.id) {
                  index, worktree in
                  WorktreeGridRow(
                    worktree: worktree,
                    allocatedBytes: worktreeAllocatedBytes[worktree.id]
                  )
                  .background(rowBackground(at: index))
                  .overlay(alignment: .bottom) { Divider() }
                }
              }
              .frame(width: WorktreeGridMetrics.contentWidth, alignment: .leading)
            }
            .frame(
              width: max(0, geometry.size.width - WorktreeGridMetrics.actionWidth - 1),
              alignment: .leading
            )

            Divider()

            VStack(spacing: 0) {
              Text("操作")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(
                  width: WorktreeGridMetrics.actionWidth,
                  height: WorktreeGridMetrics.headerHeight
                )
                .background(.bar)

              ForEach(Array(snapshot.worktrees.enumerated()), id: \.element.id) {
                index, worktree in
                WorktreeActionRow(
                  worktree: worktree,
                  isRemoving: removingWorktreeID == worktree.id,
                  isRemovalInProgress: removingWorktreeID != nil,
                  onMessage: onMessage,
                  onError: onError,
                  onRemove: onRemove
                )
                .background(rowBackground(at: index))
                .overlay(alignment: .bottom) { Divider() }
              }
            }
            .frame(width: WorktreeGridMetrics.actionWidth)
            .background(.background)
            .shadow(color: .black.opacity(0.08), radius: 3, x: -2)
          }
        }
      }
    }
    .navigationTitle(snapshot.repository.name)
  }

  private func rowBackground(at index: Int) -> Color {
    index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.035)
  }
}

private enum WorktreeGridMetrics {
  static let headerHeight: CGFloat = 30
  static let rowHeight: CGFloat = 52
  static let worktreeWidth: CGFloat = 180
  static let statusWidth: CGFloat = 140
  static let diskWidth: CGFloat = 110
  static let recommendationWidth: CGFloat = 240
  static let pathWidth: CGFloat = 420
  static let actionWidth: CGFloat = 84
  static let contentWidth =
    worktreeWidth + statusWidth + diskWidth + recommendationWidth + pathWidth
}

private struct WorktreeGridHeader: View {
  var body: some View {
    HStack(spacing: 0) {
      GridCell(width: WorktreeGridMetrics.worktreeWidth) { Text("Worktree") }
      GridCell(width: WorktreeGridMetrics.statusWidth) { Text("状态") }
      GridCell(width: WorktreeGridMetrics.diskWidth) { Text("占用空间") }
      GridCell(width: WorktreeGridMetrics.recommendationWidth) { Text("建议") }
      GridCell(width: WorktreeGridMetrics.pathWidth) { Text("路径") }
    }
    .font(.caption)
    .fontWeight(.medium)
    .foregroundStyle(.secondary)
    .frame(height: WorktreeGridMetrics.headerHeight)
    .background(.bar)
  }
}

private struct WorktreeGridRow: View {
  let worktree: GitWorktree
  let allocatedBytes: Int64?

  var body: some View {
    HStack(spacing: 0) {
      GridCell(width: WorktreeGridMetrics.worktreeWidth) {
        VStack(alignment: .leading, spacing: 3) {
          Text(worktree.branch ?? "Detached HEAD")
            .fontWeight(.medium)
            .lineLimit(1)
          if worktree.isMain {
            Text("主工作区")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }

      GridCell(width: WorktreeGridMetrics.statusWidth) {
        StatusLabel(
          status: worktree.status,
          isLocked: worktree.isLocked,
          isPrunable: worktree.isPrunable
        )
      }

      GridCell(width: WorktreeGridMetrics.diskWidth) {
        DiskUsageLabel(allocatedBytes: allocatedBytes)
      }

      GridCell(width: WorktreeGridMetrics.recommendationWidth) {
        RecommendationLabel(recommendation: worktree.cleanupRecommendation)
      }

      GridCell(width: WorktreeGridMetrics.pathWidth) {
        Text(worktree.path.path)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .textSelection(.enabled)
          .help(worktree.path.path)
      }
    }
    .frame(height: WorktreeGridMetrics.rowHeight)
  }
}

private struct GridCell<Content: View>: View {
  let width: CGFloat
  @ViewBuilder let content: Content

  var body: some View {
    content
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 10)
      .frame(width: width, alignment: .leading)
  }
}

private struct WorktreeActionRow: View {
  let worktree: GitWorktree
  let isRemoving: Bool
  let isRemovalInProgress: Bool
  let onMessage: (String) -> Void
  let onError: (String) -> Void
  let onRemove: (GitWorktree) -> Void

  var body: some View {
    HStack(spacing: 8) {
      PathActionMenu(
        path: worktree.path,
        onMessage: onMessage,
        onError: onError
      )

      if isRemoving {
        ProgressView()
          .controlSize(.small)
          .frame(width: 20, height: 20)
      } else if worktree.cleanupRecommendation.removalKind != nil {
        Button("删除", systemImage: "trash", role: .destructive) {
          onRemove(worktree)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .disabled(isRemovalInProgress)
        .help(removalHelp)
      } else {
        Color.clear.frame(width: 20, height: 20)
      }
    }
    .frame(
      width: WorktreeGridMetrics.actionWidth,
      height: WorktreeGridMetrics.rowHeight
    )
  }

  private var removalHelp: String {
    if case .unmerged = worktree.cleanupRecommendation.removalKind {
      "删除这个尚未合入的 worktree"
    } else {
      "删除这个 worktree"
    }
  }
}

private struct PathActionMenu: View {
  let path: URL
  let onMessage: (String) -> Void
  let onError: (String) -> Void

  private let service = OpenTargetService()

  var body: some View {
    Menu {
      Button {
        service.copyPath(path)
        onMessage("已复制路径：\(path.path)")
      } label: {
        Label("复制路径", systemImage: "doc.on.doc")
      }

      Divider()

      ForEach(service.availableTargets()) { target in
        Button {
          Task {
            do {
              try await service.open(path, with: target)
            } catch {
              onError(error.localizedDescription)
            }
          }
        } label: {
          Label {
            Text("使用 \(target.label) 打开")
          } icon: {
            Image(nsImage: target.icon)
          }
        }
      }
    } label: {
      Image(systemName: "arrow.up.forward.app")
        .frame(width: 20, height: 20)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("复制路径或选择打开方式")
  }
}

private struct DiskUsageLabel: View {
  private static let largeWorktreeThreshold: Int64 = 5_000_000_000

  let allocatedBytes: Int64?

  var body: some View {
    if let allocatedBytes {
      Text(formattedBytes(allocatedBytes))
        .foregroundStyle(
          allocatedBytes >= Self.largeWorktreeThreshold ? Color.orange : Color.secondary
        )
        .help(allocatedBytes >= Self.largeWorktreeThreshold ? "占用超过 5 GB，建议检查" : "")
    } else {
      Text("—")
        .foregroundStyle(.tertiary)
    }
  }
}

private struct StatusLabel: View {
  let status: WorktreeStatus?
  let isLocked: Bool
  let isPrunable: Bool

  var body: some View {
    if isPrunable {
      Label("路径缺失", systemImage: "questionmark.folder.fill")
        .foregroundStyle(.red)
    } else if isLocked {
      Label("已锁定", systemImage: "lock.fill")
        .foregroundStyle(.orange)
    } else if status?.isClean == true {
      Label("干净", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
    } else if status != nil {
      Label(summary, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
    }
  }

  private var summary: String {
    guard let status else { return "状态不可用" }
    let count =
      status.stagedFileCount
      + status.modifiedFileCount
      + status.untrackedFileCount
      + status.conflictedFileCount
    return "\(count) 项变更"
  }
}

private struct RecommendationLabel: View {
  let recommendation: CleanupRecommendation

  var body: some View {
    switch recommendation {
    case .protectedMainWorktree:
      Label("保留主工作区", systemImage: "shield.fill")
        .foregroundStyle(.secondary)
    case .blocked(let reasons):
      Label(blockedTitle(reasons), systemImage: "xmark.octagon.fill")
        .foregroundStyle(.red)
    case .needsReview(let reason):
      Label(reviewTitle(reason), systemImage: "questionmark.circle.fill")
        .foregroundStyle(.orange)
    case .cleanable(let target):
      Label("已合入 \(target)，可清理", systemImage: "trash.circle.fill")
        .foregroundStyle(.green)
    }
  }

  private func blockedTitle(_ reasons: [CleanupBlocker]) -> String {
    if reasons.contains(where: {
      if case .missing = $0 { true } else { false }
    }) {
      return "路径缺失，需清理登记"
    }
    if reasons.contains(.uncommittedChanges) {
      return "有未提交修改"
    }
    if case .locked(let reason) = reasons.first {
      return reason.map { "已锁定：\($0)" } ?? "已锁定"
    }
    return "不可清理"
  }

  private func reviewTitle(_ reason: CleanupReviewReason) -> String {
    switch reason {
    case .cleanupTargetUnavailable:
      "未识别远端默认分支"
    case .notMerged(let target):
      "尚未合入 \(target)"
    }
  }
}

private func formattedBytes(_ bytes: Int64) -> String {
  ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

private enum WorktreeRemovalKind {
  case merged(target: String)
  case unmerged(target: String)
}

extension CleanupRecommendation {
  fileprivate var removalKind: WorktreeRemovalKind? {
    switch self {
    case .cleanable(let target):
      .merged(target: target)
    case .needsReview(reason: .notMerged(let target)):
      .unmerged(target: target)
    default:
      nil
    }
  }
}
