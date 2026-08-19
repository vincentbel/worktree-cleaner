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
        if model.repositories.isEmpty, model.baseDirectoryURL != nil, !model.isScanning {
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
        if model.isScanning || model.isLoadingSnapshot {
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
    .confirmationDialog(
      "确认清理这个 worktree？",
      isPresented: Binding(
        get: { pendingRemoval != nil },
        set: { if !$0 { pendingRemoval = nil } }
      ),
      titleVisibility: .visible,
      presenting: pendingRemoval
    ) { worktree in
      Button("永久删除 worktree", role: .destructive) {
        pendingRemoval = nil
        Task { await model.remove(worktree) }
      }
      Button("取消", role: .cancel) {
        pendingRemoval = nil
      }
    } message: { worktree in
      Text(
        "将通过 Git 删除 \(worktree.path.path)。此操作不可撤销，但不会删除分支。执行前会重新检查 Git 状态。"
      )
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
      WorktreeTable(snapshot: snapshot) { worktree in
        pendingRemoval = worktree
      }
    } else if model.isScanning || model.isLoadingSnapshot {
      ProgressView("正在读取 Git 状态…")
    } else {
      ContentUnavailableView(
        "选择一个项目",
        systemImage: "point.3.connected.trianglepath.dotted"
      )
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
  let onRemove: (GitWorktree) -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("\(snapshot.worktrees.count) 个 worktree")
        Spacer()
        Label(
          "共享 Git 数据 \(formattedBytes(snapshot.sharedGitAllocatedBytes))",
          systemImage: "externaldrive"
        )
        .foregroundStyle(.secondary)
      }
      .font(.callout)
      .padding(.horizontal)
      .padding(.vertical, 10)

      Divider()

      Table(snapshot.worktrees) {
        TableColumn("Worktree") { worktree in
          VStack(alignment: .leading, spacing: 3) {
            Text(worktree.branch ?? "Detached HEAD")
              .fontWeight(.medium)
            if worktree.isMain {
              Text("主工作区")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
        .width(min: 140, ideal: 180)

        TableColumn("状态") { worktree in
          StatusLabel(
            status: worktree.status,
            isLocked: worktree.isLocked,
            isPrunable: worktree.isPrunable
          )
        }
        .width(min: 110, ideal: 140)

        TableColumn("占用空间") { worktree in
          DiskUsageLabel(allocatedBytes: worktree.allocatedBytes)
        }
        .width(min: 90, ideal: 110)

        TableColumn("建议") { worktree in
          RecommendationLabel(recommendation: worktree.cleanupRecommendation)
        }
        .width(min: 180, ideal: 240)

        TableColumn("路径") { worktree in
          Text(worktree.path.path)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .help(worktree.path.path)
        }
        .width(min: 240, ideal: 420)

        TableColumn("") { worktree in
          if worktree.cleanupRecommendation.isCleanable {
            Button("清理", systemImage: "trash", role: .destructive) {
              onRemove(worktree)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("清理这个 worktree")
          }
        }
        .width(32)
      }
    }
    .navigationTitle(snapshot.repository.name)
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

extension CleanupRecommendation {
  fileprivate var isCleanable: Bool {
    if case .cleanable = self {
      true
    } else {
      false
    }
  }
}
