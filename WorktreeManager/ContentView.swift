import SwiftUI
import UniformTypeIdentifiers
import WorktreeCore

struct ContentView: View {
  @State private var model = AppState()
  @State private var isChoosingDirectory = false

  var body: some View {
    @Bindable var model = model

    NavigationSplitView {
      List(model.repositories, selection: $model.selectedRepositoryID) { repository in
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
    .task {
      await model.restoreSelectedDirectory()
    }
    .onChange(of: model.selectedRepositoryID) {
      Task { await model.loadSelectedRepository() }
    }
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
      WorktreeTable(snapshot: snapshot)
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

  var body: some View {
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
        StatusLabel(status: worktree.status, isLocked: worktree.isLocked)
      }
      .width(min: 110, ideal: 140)

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
    }
    .navigationTitle(snapshot.repository.name)
  }
}

private struct StatusLabel: View {
  let status: WorktreeStatus
  let isLocked: Bool

  var body: some View {
    if isLocked {
      Label("已锁定", systemImage: "lock.fill")
        .foregroundStyle(.orange)
    } else if status.isClean {
      Label("干净", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
    } else {
      Label(summary, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
    }
  }

  private var summary: String {
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
