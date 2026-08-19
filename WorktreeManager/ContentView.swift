import SwiftUI
import UniformTypeIdentifiers
import WorktreeCore

struct ContentView: View {
  @State private var model = AppState()
  @State private var isChoosingDirectory = false
  @State private var pendingRemoval: GitWorktree?

  var body: some View {
    NavigationSplitView {
      List(selection: repositorySelection) {
        if !repositoriesWithLinkedWorktrees.isEmpty {
          Section {
            ForEach(repositoriesWithLinkedWorktrees) { repository in
              RepositoryRow(repository: repository)
                .tag(repository.id)
            }
          } header: {
            Text(
              L10n.plural(
                "sidebar.section.with_linked",
                count: repositoriesWithLinkedWorktrees.count
              )
            )
          }
        }

        if !repositoriesWithoutLinkedWorktrees.isEmpty {
          Section {
            ForEach(repositoriesWithoutLinkedWorktrees) { repository in
              RepositoryRow(repository: repository)
                .tag(repository.id)
            }
          } header: {
            Text(
              L10n.plural(
                "sidebar.section.main_only",
                count: repositoriesWithoutLinkedWorktrees.count
              )
            )
          }
        }
      }
      .navigationTitle(L10n.string("sidebar.title"))
      .overlay {
        if model.repositories.isEmpty, model.isScanning {
          ProgressView(L10n.string("sidebar.scanning"))
        } else if model.repositories.isEmpty, model.baseDirectoryURL != nil {
          ContentUnavailableView(
            L10n.string("sidebar.empty.title"),
            systemImage: "folder.badge.questionmark",
            description: Text(L10n.string("sidebar.empty.description"))
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
            .padding(.leading, 6)
        }

        Button(L10n.string("toolbar.choose_directory"), systemImage: "folder.badge.plus") {
          isChoosingDirectory = true
        }

        Button(L10n.string("toolbar.refresh"), systemImage: "arrow.clockwise") {
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
      L10n.string("alert.operation_failed"),
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: { if !$0 { model.errorMessage = nil } }
      )
    ) {
      Button(L10n.string("common.ok"), role: .cancel) {}
    } message: {
      Text(model.errorMessage ?? L10n.string("error.unknown"))
    }
    .alert(
      L10n.string("alert.operation_completed"),
      isPresented: Binding(
        get: { model.successMessage != nil },
        set: { if !$0 { model.successMessage = nil } }
      )
    ) {
      Button(L10n.string("common.ok"), role: .cancel) {}
    } message: {
      Text(model.successMessage ?? L10n.string("success.operation_completed"))
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
      Button(L10n.string("common.cancel"), role: .cancel) {
        pendingRemoval = nil
      }
    } message: { worktree in
      Text(removalMessage(for: worktree))
    }
    .task {
      await model.restoreSelectedDirectory()
    }
    .overlay(alignment: .bottom) {
      if let transientMessage = model.transientMessage {
        Label(transientMessage, systemImage: "checkmark.circle.fill")
          .font(.callout)
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(.regularMaterial, in: Capsule())
          .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
          .padding(.bottom, 18)
          .allowsHitTesting(false)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.easeOut(duration: 0.18), value: model.transientMessage)
  }

  private var repositoriesWithLinkedWorktrees: [GitRepository] {
    model.repositories.filter { $0.linkedWorktreeCount > 0 }
  }

  private var repositoriesWithoutLinkedWorktrees: [GitRepository] {
    model.repositories.filter { $0.linkedWorktreeCount == 0 }
  }

  private var repositorySelection: Binding<GitRepository.ID?> {
    Binding(
      get: { model.selectedRepositoryID },
      set: { repositoryID in
        guard model.selectedRepositoryID != repositoryID else { return }
        Task { await model.selectRepository(repositoryID) }
      }
    )
  }

  @ViewBuilder
  private var detail: some View {
    if model.baseDirectoryURL == nil {
      ContentUnavailableView {
        Label(L10n.string("empty.choose_base_directory"), systemImage: "folder.badge.plus")
      } description: {
        Text(L10n.string("empty.choose_base_description"))
      } actions: {
        Button(L10n.string("toolbar.choose_directory")) {
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
        diskUsageMeasuredAt: model.diskUsageMeasuredAt,
        isMeasuringDiskUsage: model.isMeasuringDiskUsage,
        isDiskUsageRefreshDisabled: model.isLoadingSnapshot || model.isMeasuringDiskUsage,
        removingWorktreeID: model.removingWorktreeID,
        onRecalculateDiskUsage: { model.recalculateDiskUsage() },
        onMessage: { model.showTransientMessage($0) },
        onError: { model.errorMessage = $0 },
        onRemove: { pendingRemoval = $0 }
      )
    } else if model.isScanning || model.isLoadingSnapshot {
      ProgressView(L10n.string("detail.loading_git_status"))
    } else {
      ContentUnavailableView(
        L10n.string("detail.select_project"),
        systemImage: "point.3.connected.trianglepath.dotted"
      )
    }
  }

  private var removalTitle: String {
    guard let pendingRemoval else { return L10n.string("removal.confirm.title") }
    switch pendingRemoval.cleanupRecommendation.removalKind {
    case .unmerged(let target):
      return L10n.format("removal.unmerged.title", target)
    default:
      return L10n.string("removal.confirm.title")
    }
  }

  private func removalButtonTitle(for worktree: GitWorktree) -> String {
    switch worktree.cleanupRecommendation.removalKind {
    case .unmerged:
      L10n.string("removal.unmerged.button")
    default:
      L10n.string("removal.permanent.button")
    }
  }

  private func removalMessage(for worktree: GitWorktree) -> String {
    switch worktree.cleanupRecommendation.removalKind {
    case .unmerged(let target):
      let recoveryMessage =
        worktree.branch.map {
          L10n.format("removal.branch_preserved", $0)
        } ?? L10n.format("removal.detached_warning", worktree.head)
      return L10n.format(
        "removal.unmerged.message",
        target,
        recoveryMessage,
        worktree.path.path
      )
    default:
      return L10n.format("removal.confirm.message", worktree.path.path)
    }
  }
}

private struct RepositoryRow: View {
  let repository: GitRepository

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 3) {
        Text(repository.name)
          .fontWeight(.medium)
        Text(repository.workingTreeURL.path)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 4)

      if repository.linkedWorktreeCount > 0 {
        Label(
          "\(repository.linkedWorktreeCount)",
          systemImage: "square.stack.3d.up.fill"
        )
        .font(.caption.monospacedDigit())
        .foregroundStyle(.primary)
        .help(
          L10n.plural(
            "sidebar.extra_count_help",
            count: repository.linkedWorktreeCount
          )
        )
      } else {
        Text(L10n.string("sidebar.no_extra"))
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
    }
    .padding(.vertical, 3)
    .opacity(repository.linkedWorktreeCount == 0 ? 0.58 : 1)
  }
}

private struct WorktreeTable: View {
  let snapshot: RepositorySnapshot
  let worktreeAllocatedBytes: [URL: Int64]
  let sharedGitAllocatedBytes: Int64?
  let diskUsageMeasuredAt: Date?
  let isMeasuringDiskUsage: Bool
  let isDiskUsageRefreshDisabled: Bool
  let removingWorktreeID: GitWorktree.ID?
  let onRecalculateDiskUsage: () -> Void
  let onMessage: (String) -> Void
  let onError: (String) -> Void
  let onRemove: (GitWorktree) -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(L10n.plural("table.worktree_count", count: snapshot.worktrees.count))
        Spacer()
        if let sharedGitAllocatedBytes {
          Label(
            L10n.format("table.shared_git_data", formattedBytes(sharedGitAllocatedBytes)),
            systemImage: "externaldrive"
          )
          .foregroundStyle(.secondary)
        } else {
          Label(L10n.string("table.calculating_shared_git"), systemImage: "externaldrive")
            .foregroundStyle(.secondary)
        }
        if isMeasuringDiskUsage {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel(L10n.string("table.calculating_disk_usage"))
        }
        if let diskUsageMeasuredAt {
          Text(
            L10n.format(
              "table.disk_usage_measured_at",
              formattedMeasurementDate(diskUsageMeasuredAt)
            )
          )
          .font(.caption)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
        }
        Button(action: onRecalculateDiskUsage) {
          Label(
            L10n.string("action.recalculate_disk_usage.short"),
            systemImage: "arrow.clockwise"
          )
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isDiskUsageRefreshDisabled)
        .help(L10n.string("action.recalculate_disk_usage"))
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
                    allocatedBytes: worktreeAllocatedBytes[worktree.id],
                    isMeasuringDiskUsage: isMeasuringDiskUsage
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
              Text(L10n.string("column.actions"))
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
  static let worktreeWidth: CGFloat = 260
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
      GridCell(width: WorktreeGridMetrics.worktreeWidth) {
        Text(L10n.string("column.worktree"))
      }
      GridCell(width: WorktreeGridMetrics.statusWidth) { Text(L10n.string("column.status")) }
      GridCell(width: WorktreeGridMetrics.diskWidth) {
        Text(L10n.string("column.disk_usage"))
      }
      GridCell(width: WorktreeGridMetrics.recommendationWidth) {
        Text(L10n.string("column.recommendation"))
      }
      GridCell(width: WorktreeGridMetrics.pathWidth) { Text(L10n.string("column.path")) }
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
  let isMeasuringDiskUsage: Bool

  var body: some View {
    HStack(spacing: 0) {
      GridCell(width: WorktreeGridMetrics.worktreeWidth) {
        VStack(alignment: .leading, spacing: 3) {
          Text(worktree.branch ?? "Detached HEAD")
            .fontWeight(.medium)
            .lineLimit(1)
          if worktree.isMain {
            Text(L10n.string("worktree.main"))
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
        DiskUsageLabel(
          allocatedBytes: allocatedBytes,
          isMeasuring: isMeasuringDiskUsage
        )
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
          .frame(width: 24, height: 24)
      } else if worktree.cleanupRecommendation.removalKind != nil {
        Button {
          onRemove(worktree)
        } label: {
          WorktreeActionIcon(systemName: "trash", pointSize: 13)
            .foregroundStyle(removalNeedsReview ? .secondary : .primary)
        }
        .buttonStyle(.plain)
        .disabled(isRemovalInProgress)
        .help(removalHelp)
        .accessibilityLabel(L10n.string("action.delete"))
      } else {
        Color.clear.frame(width: 24, height: 24)
      }
    }
    .frame(
      width: WorktreeGridMetrics.actionWidth,
      height: WorktreeGridMetrics.rowHeight
    )
  }

  private var removalHelp: String {
    if case .unmerged = worktree.cleanupRecommendation.removalKind {
      L10n.string("action.delete.unmerged_help")
    } else {
      L10n.string("action.delete.help")
    }
  }

  private var removalNeedsReview: Bool {
    if case .unmerged = worktree.cleanupRecommendation.removalKind {
      true
    } else {
      false
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
        onMessage(L10n.string("action.path_copied"))
      } label: {
        Label(L10n.string("action.copy_path"), systemImage: "doc.on.doc")
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
            Text(L10n.format("action.open_with", target.label))
          } icon: {
            Image(nsImage: target.icon)
          }
        }
      }
    } label: {
      WorktreeActionIcon(systemName: "ellipsis.circle", pointSize: 17)
        .foregroundStyle(.primary)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help(L10n.string("action.path_menu.help"))
    .accessibilityLabel(L10n.string("action.path_menu.label"))
  }
}

private struct WorktreeActionIcon: View {
  let systemName: String
  var pointSize: CGFloat = 15

  var body: some View {
    Image(systemName: systemName)
      .font(.system(size: pointSize, weight: .regular))
      .symbolRenderingMode(.monochrome)
      .frame(width: 24, height: 24)
  }
}

private struct DiskUsageLabel: View {
  private static let largeWorktreeThreshold: Int64 = 5_000_000_000

  let allocatedBytes: Int64?
  let isMeasuring: Bool

  var body: some View {
    if let allocatedBytes {
      HStack(spacing: 6) {
        Text(formattedBytes(allocatedBytes))
          .foregroundStyle(
            allocatedBytes >= Self.largeWorktreeThreshold ? Color.orange : Color.secondary
          )
          .help(
            allocatedBytes >= Self.largeWorktreeThreshold ? L10n.string("disk.large_help") : ""
          )
        if isMeasuring {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel(L10n.string("table.calculating_disk_usage"))
        }
      }
    } else if isMeasuring {
      ProgressView()
        .controlSize(.small)
        .accessibilityLabel(L10n.string("table.calculating_disk_usage"))
    } else {
      Text("—")
        .foregroundStyle(.tertiary)
    }
  }
}

private func formattedMeasurementDate(_ date: Date) -> String {
  date.formatted(
    .dateTime
      .month(.abbreviated)
      .day()
      .hour()
      .minute()
  )
}

private struct StatusLabel: View {
  let status: WorktreeStatus?
  let isLocked: Bool
  let isPrunable: Bool

  var body: some View {
    if isPrunable {
      Label(L10n.string("status.missing_path"), systemImage: "questionmark.folder.fill")
        .foregroundStyle(.red)
    } else if isLocked {
      Label(L10n.string("status.locked"), systemImage: "lock.fill")
        .foregroundStyle(.orange)
    } else if status?.isClean == true {
      Label(L10n.string("status.clean"), systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
    } else if status != nil {
      Label(summary, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
    }
  }

  private var summary: String {
    guard let status else { return L10n.string("status.unavailable") }
    let count =
      status.stagedFileCount
      + status.modifiedFileCount
      + status.untrackedFileCount
      + status.conflictedFileCount
    return L10n.plural("status.change_count", count: count)
  }
}

private struct RecommendationLabel: View {
  let recommendation: CleanupRecommendation

  var body: some View {
    switch recommendation {
    case .protectedMainWorktree:
      Label(L10n.string("recommendation.keep_main"), systemImage: "shield.fill")
        .foregroundStyle(.secondary)
    case .blocked(let reasons):
      Label(blockedTitle(reasons), systemImage: "xmark.octagon.fill")
        .foregroundStyle(.red)
    case .needsReview(let reason):
      Label(reviewTitle(reason), systemImage: "questionmark.circle.fill")
        .foregroundStyle(.orange)
    case .cleanable(let target):
      Label(L10n.format("recommendation.cleanable", target), systemImage: "trash.circle.fill")
        .foregroundStyle(.green)
    }
  }

  private func blockedTitle(_ reasons: [CleanupBlocker]) -> String {
    if reasons.contains(where: {
      if case .missing = $0 { true } else { false }
    }) {
      return L10n.string("recommendation.missing_path")
    }
    if reasons.contains(.uncommittedChanges) {
      return L10n.string("recommendation.uncommitted")
    }
    if case .locked(let reason) = reasons.first {
      return reason.map { L10n.format("recommendation.locked_reason", $0) }
        ?? L10n.string("status.locked")
    }
    return L10n.string("recommendation.blocked")
  }

  private func reviewTitle(_ reason: CleanupReviewReason) -> String {
    switch reason {
    case .cleanupTargetUnavailable:
      L10n.string("recommendation.cleanup_target_unavailable")
    case .notMerged(let target):
      L10n.format("recommendation.not_merged", target)
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
