import SwiftUI
import UniformTypeIdentifiers
import WorktreeCore

struct ContentView: View {
  let model: AppState

  @Environment(\.openSettings) private var openSettings
  @State private var isChoosingDirectory = false
  @State private var pendingRemoval: GitWorktree?
  @State private var pendingBatchRemoval: BatchRemovalRequest?
  @State private var pendingPrune: GitWorktree?

  var body: some View {
    NavigationSplitView {
      VStack(spacing: 0) {
        HStack(spacing: 8) {
          Picker(L10n.string("sidebar.scope.label"), selection: rootSelection) {
            Text(
              L10n.plural(
                "sidebar.scope.all",
                count: model.workspaceRoots.urls.count
              )
            )
            .tag(URL?.none)

            ForEach(model.workspaceRoots.urls, id: \.self) { rootURL in
              Text(rootURL.lastPathComponent)
                .tag(Optional(rootURL))
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(maxWidth: .infinity, alignment: .leading)
          .disabled(model.workspaceRoots.urls.isEmpty)

          Button {
            Task { await model.scanSelectedScope() }
          } label: {
            ZStack {
              Image(systemName: "arrow.clockwise")
                .opacity(model.isScanningCurrentScope ? 0 : 1)
              if model.isScanningCurrentScope {
                ProgressView()
                  .controlSize(.small)
              }
            }
            .frame(width: 16, height: 16)
          }
          .buttonStyle(.borderless)
          .disabled(model.workspaceRoots.urls.isEmpty || model.isScanningCurrentScope)
          .help(L10n.string("sidebar.rescan_help"))
          .accessibilityLabel(
            L10n.string(model.isScanningCurrentScope ? "sidebar.scanning" : "sidebar.rescan")
          )

          Button(L10n.string("toolbar.add_directory"), systemImage: "plus") {
            isChoosingDirectory = true
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
          .help(L10n.string("toolbar.add_directory"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)

        Divider()

        List(selection: repositorySelection) {
          if !repositoriesWithLinkedWorktrees.isEmpty {
            Section {
              ForEach(repositoriesWithLinkedWorktrees) { repository in
                RepositoryRow(
                  repository: repository,
                  measuredTotalAllocatedBytes: model.measuredTotalAllocatedBytes(
                    for: repository.id
                  )
                )
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
                RepositoryRow(
                  repository: repository,
                  measuredTotalAllocatedBytes: model.measuredTotalAllocatedBytes(
                    for: repository.id
                  )
                )
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
        .contentMargins(.top, 8, for: .scrollContent)
        .overlay {
          if model.visibleRepositories.isEmpty, model.isScanningCurrentScope {
            ProgressView(L10n.string("sidebar.scanning"))
          } else if model.visibleRepositories.isEmpty,
            !model.workspaceRoots.urls.isEmpty
          {
            ContentUnavailableView(
              L10n.string("sidebar.empty.title"),
              systemImage: "folder.badge.questionmark",
              description: Text(L10n.string("sidebar.empty.description"))
            )
          }
        }

        if !model.workspaceRoots.urls.isEmpty {
          Divider()
          Button {
            openSettings()
          } label: {
            HStack {
              Text(
                L10n.plural(
                  "sidebar.base_directory_count",
                  count: model.workspaceRoots.urls.count
                )
              )
              Spacer()
              Text(L10n.string("sidebar.manage_directories"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .padding(10)
          .background(.bar)
        }
      }
      .navigationTitle(L10n.string("sidebar.title"))
      .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
    } detail: {
      detail
    }
    .toolbar {
      ToolbarItemGroup {
        Button {
          Task { await model.loadSelectedRepository() }
        } label: {
          ZStack {
            Image(systemName: "arrow.clockwise")
              .opacity(model.isLoadingSnapshot ? 0 : 1)
            if model.isLoadingSnapshot {
              ProgressView()
                .controlSize(.small)
            }
          }
          .frame(width: 20, height: 20)
        }
        .disabled(model.selectedRepositoryID == nil || model.isLoadingSnapshot)
        .help(L10n.string("toolbar.refresh_selected_project"))
        .accessibilityLabel(
          L10n.string(model.isLoadingSnapshot ? "detail.loading_git_status" : "toolbar.refresh")
        )
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
      Task { await model.addDirectory(url) }
    }
    .sheet(item: $pendingBatchRemoval) { request in
      BatchRemovalConfirmationSheet(request: request) {
        pendingBatchRemoval = nil
        Task { await model.removeAll(request.worktrees) }
      }
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
    .alert(
      L10n.string("prune.confirm.title"),
      isPresented: Binding(
        get: { pendingPrune != nil },
        set: { if !$0 { pendingPrune = nil } }
      ),
      presenting: pendingPrune
    ) { worktree in
      Button(L10n.string("prune.confirm.button")) {
        pendingPrune = nil
        Task { await model.prune(worktree) }
      }
      Button(L10n.string("common.cancel"), role: .cancel) {
        pendingPrune = nil
      }
    } message: { worktree in
      Text(L10n.format("prune.confirm.message", worktree.path.path))
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
    model.visibleRepositories.filter { $0.linkedWorktreeCount > 0 }
  }

  private var repositoriesWithoutLinkedWorktrees: [GitRepository] {
    model.visibleRepositories.filter { $0.linkedWorktreeCount == 0 }
  }

  private var rootSelection: Binding<URL?> {
    Binding(
      get: { model.selectedRootID },
      set: { rootID in
        guard model.selectedRootID != rootID else { return }
        Task { await model.selectRoot(rootID) }
      }
    )
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
    if model.workspaceRoots.urls.isEmpty {
      ContentUnavailableView {
        Label(L10n.string("empty.choose_base_directory"), systemImage: "folder.badge.plus")
      } description: {
        Text(L10n.string("empty.choose_base_description"))
      } actions: {
        Button(L10n.string("empty.add_directory")) {
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
        batchRemovalProgress: model.batchRemovalProgress,
        onRecalculateDiskUsage: { model.recalculateDiskUsage() },
        onMessage: { model.showTransientMessage($0) },
        onError: { model.errorMessage = $0 },
        onRemove: { pendingRemoval = $0 },
        onBatchRemove: { worktrees in
          pendingBatchRemoval = BatchRemovalRequest(worktrees: worktrees)
        },
        onPrune: { pendingPrune = $0 }
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
    case .unmerged:
      return L10n.format("removal.unmerged.message", worktree.path.path)
    default:
      return L10n.format("removal.confirm.message", worktree.path.path)
    }
  }

}

private struct BatchRemovalRequest: Identifiable {
  let id = UUID()
  let worktrees: [GitWorktree]

  var unmergedCount: Int {
    worktrees.count { worktree in
      if case .unmerged = worktree.cleanupRecommendation.removalKind {
        return true
      }
      return false
    }
  }

  var mergedCount: Int {
    worktrees.count - unmergedCount
  }
}

private struct BatchRemovalConfirmationSheet: View {
  let request: BatchRemovalRequest
  let onConfirm: () -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: headerSystemImage)
          .font(.system(size: 32, weight: .semibold))
          .foregroundStyle(headerColor)
          .frame(width: 40, height: 40)

        VStack(alignment: .leading, spacing: 5) {
          Text(L10n.plural("batch.confirm.title", count: request.worktrees.count))
            .font(.title2.weight(.semibold))
          Text(L10n.string("batch.confirm.subtitle"))
            .foregroundStyle(.secondary)
        }
      }

      selectionBreakdown

      Divider()

      HStack {
        Spacer()
        Button(L10n.string("common.cancel")) {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)

        Button(role: .destructive) {
          dismiss()
          onConfirm()
        } label: {
          Text(L10n.plural("batch.confirm_button", count: request.worktrees.count))
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 540)
  }

  @ViewBuilder
  private var selectionBreakdown: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(L10n.string("batch.confirm.breakdown.title"))
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.bottom, 4)

      if request.mergedCount > 0 {
        BatchRemovalBreakdownRow(
          count: request.mergedCount,
          title: L10n.string("batch.confirm.breakdown.merged"),
          detail: L10n.string("batch.confirm.breakdown.merged.detail"),
          systemImage: "checkmark.circle.fill",
          tint: .green
        )
      }

      if request.mergedCount > 0, request.unmergedCount > 0 {
        Divider()
          .padding(.leading, 34)
      }

      if request.unmergedCount > 0 {
        BatchRemovalBreakdownRow(
          count: request.unmergedCount,
          title: L10n.string("batch.confirm.breakdown.unmerged"),
          detail: L10n.string("batch.confirm.breakdown.unmerged.detail"),
          systemImage: "exclamationmark.triangle.fill",
          tint: .orange
        )
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    }
  }

  private var headerSystemImage: String {
    request.unmergedCount > 0 ? "exclamationmark.triangle.fill" : "trash.circle.fill"
  }

  private var headerColor: Color {
    request.unmergedCount > 0 ? .orange : .red
  }
}

private struct BatchRemovalBreakdownRow: View {
  let count: Int
  let title: String
  let detail: String
  let systemImage: String
  let tint: Color

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: systemImage)
        .foregroundStyle(tint)
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.callout.weight(.medium))
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 12)

      Text(count.formatted())
        .font(.title3.weight(.semibold).monospacedDigit())
    }
    .padding(.vertical, 9)
  }
}

private struct RepositoryRow: View {
  let repository: GitRepository
  let measuredTotalAllocatedBytes: Int64?

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

      VStack(alignment: .trailing, spacing: 3) {
        if repository.linkedWorktreeCount > 0 {
          RepositoryMetricLabel(
            value: "\(repository.linkedWorktreeCount)",
            systemImage: "square.stack.3d.up.fill"
          )
          .help(
            L10n.plural(
              "sidebar.extra_count_help",
              count: repository.linkedWorktreeCount
            )
          )
        }

        if let measuredTotalAllocatedBytes {
          let size = formattedBytes(measuredTotalAllocatedBytes)
          RepositoryMetricLabel(value: size, systemImage: "internaldrive")
            .help(L10n.format("sidebar.total_size_help", size))
        }
      }
      .font(.caption.monospacedDigit())
      .foregroundStyle(.secondary)
      .lineLimit(1)
    }
    .padding(.vertical, 3)
    .opacity(repository.linkedWorktreeCount == 0 ? 0.58 : 1)
  }
}

private struct RepositoryMetricLabel: View {
  let value: String
  let systemImage: String

  var body: some View {
    HStack(spacing: 2) {
      Image(systemName: systemImage)
      Text(value)
    }
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
  let batchRemovalProgress: BatchRemovalProgress?
  let onRecalculateDiskUsage: () -> Void
  let onMessage: (String) -> Void
  let onError: (String) -> Void
  let onRemove: (GitWorktree) -> Void
  let onBatchRemove: ([GitWorktree]) -> Void
  let onPrune: (GitWorktree) -> Void

  @State private var selectedBatchRemovalIDs: Set<GitWorktree.ID> = []

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(L10n.plural("table.worktree_count", count: snapshot.worktrees.count))
        Text(
          L10n.format(
            "batch.selected_count",
            selectedBatchRemovalWorktrees.count
          )
        )
        .foregroundStyle(.secondary)

        Button {
          onBatchRemove(selectedBatchRemovalWorktrees)
        } label: {
          Label(batchRemovalButtonTitle, systemImage: "trash")
            .foregroundStyle(.red)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(.red)
        .disabled(
          selectedBatchRemovalWorktrees.isEmpty
            || removingWorktreeID != nil
            || batchRemovalProgress != nil
        )
        .help(L10n.string("action.batch_cleanup.help"))

        if let batchRemovalProgress {
          Label(
            L10n.format(
              "batch.progress",
              batchRemovalProgress.currentCount,
              batchRemovalProgress.totalCount
            ),
            systemImage: "trash"
          )
          .foregroundStyle(.secondary)
          .lineLimit(1)
        }

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
                WorktreeGridHeader(
                  selections: batchRemovalSelectableWorktrees.map {
                    batchSelection(for: $0)
                  },
                  isSelectionDisabled: isRemovalInProgress || batchRemovalSelectableIDs.isEmpty
                )
                ForEach(Array(snapshot.worktrees.enumerated()), id: \.element.id) {
                  index, worktree in
                  WorktreeGridRow(
                    worktree: worktree,
                    allocatedBytes: worktreeAllocatedBytes[worktree.id],
                    isMeasuringDiskUsage: isMeasuringDiskUsage,
                    isSelectedForBatchRemoval: batchSelection(for: worktree),
                    isBatchSelectionEnabled: isBatchRemovable(worktree) && !isRemovalInProgress
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
                  isRemovalInProgress: removingWorktreeID != nil || batchRemovalProgress != nil,
                  onMessage: onMessage,
                  onError: onError,
                  onRemove: onRemove,
                  onPrune: onPrune
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
    .onAppear {
      selectedBatchRemovalIDs = defaultBatchRemovalIDs
    }
    .onChange(of: snapshot.repository.id) {
      selectedBatchRemovalIDs = defaultBatchRemovalIDs
    }
    .onChange(of: batchRemovalSelectableIDs) { _, currentIDs in
      selectedBatchRemovalIDs.formIntersection(currentIDs)
    }
    .onChange(of: defaultBatchRemovalIDs) { previousIDs, currentIDs in
      selectedBatchRemovalIDs.subtract(previousIDs.subtracting(currentIDs))
      selectedBatchRemovalIDs.formUnion(currentIDs.subtracting(previousIDs))
    }
  }

  private var defaultBatchRemovalWorktrees: [GitWorktree] {
    snapshot.worktrees.filter(isCleanable)
  }

  private var defaultBatchRemovalIDs: Set<GitWorktree.ID> {
    Set(defaultBatchRemovalWorktrees.map(\.id))
  }

  private var batchRemovalSelectableWorktrees: [GitWorktree] {
    snapshot.worktrees.filter(isBatchRemovable)
  }

  private var batchRemovalSelectableIDs: Set<GitWorktree.ID> {
    Set(batchRemovalSelectableWorktrees.map(\.id))
  }

  private var selectedBatchRemovalWorktrees: [GitWorktree] {
    batchRemovalSelectableWorktrees.filter { selectedBatchRemovalIDs.contains($0.id) }
  }

  private var batchRemovalButtonTitle: String {
    guard !selectedBatchRemovalWorktrees.isEmpty else {
      return L10n.string("action.batch_cleanup")
    }
    return L10n.plural(
      "batch.delete_button",
      count: selectedBatchRemovalWorktrees.count
    )
  }

  private var isRemovalInProgress: Bool {
    removingWorktreeID != nil || batchRemovalProgress != nil
  }

  private func batchSelection(for worktree: GitWorktree) -> Binding<Bool> {
    Binding(
      get: { selectedBatchRemovalIDs.contains(worktree.id) },
      set: { isSelected in
        if isSelected {
          selectedBatchRemovalIDs.insert(worktree.id)
        } else {
          selectedBatchRemovalIDs.remove(worktree.id)
        }
      }
    )
  }

  private func isCleanable(_ worktree: GitWorktree) -> Bool {
    if case .cleanable = worktree.cleanupRecommendation {
      return true
    }
    return false
  }

  private func isBatchRemovable(_ worktree: GitWorktree) -> Bool {
    switch worktree.cleanupRecommendation {
    case .cleanable, .needsReview(reason: .notMerged):
      return true
    default:
      return false
    }
  }

  private func rowBackground(at index: Int) -> Color {
    index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.035)
  }
}

private enum WorktreeGridMetrics {
  static let headerHeight: CGFloat = 30
  static let rowHeight: CGFloat = 56
  static let selectionWidth: CGFloat = 44
  static let worktreeWidth: CGFloat = 260
  static let statusWidth: CGFloat = 160
  static let diskWidth: CGFloat = 110
  static let recommendationWidth: CGFloat = 330
  static let pathWidth: CGFloat = 420
  static let actionWidth: CGFloat = 84
  static let contentWidth =
    selectionWidth + worktreeWidth + statusWidth + diskWidth + recommendationWidth + pathWidth
}

private struct WorktreeGridHeader: View {
  let selections: [Binding<Bool>]
  let isSelectionDisabled: Bool

  var body: some View {
    HStack(spacing: 0) {
      GridCell(width: WorktreeGridMetrics.selectionWidth) {
        Toggle("", sources: selections, isOn: \.self)
          .labelsHidden()
          .clearDisabledCheckboxStyle()
          .disabled(isSelectionDisabled)
          .help(L10n.string("batch.select_all.help"))
          .accessibilityLabel(L10n.string("batch.select_all.label"))
      }
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
  @Binding var isSelectedForBatchRemoval: Bool
  let isBatchSelectionEnabled: Bool

  var body: some View {
    HStack(spacing: 0) {
      GridCell(width: WorktreeGridMetrics.selectionWidth) {
        Toggle("", isOn: $isSelectedForBatchRemoval)
          .labelsHidden()
          .clearDisabledCheckboxStyle()
          .disabled(!isBatchSelectionEnabled)
          .accessibilityLabel(
            L10n.format(
              "batch.select_worktree.label",
              worktree.branch ?? "Detached HEAD"
            )
          )
      }
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
  let onPrune: (GitWorktree) -> Void

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
      } else if worktree.isPrunable, !worktree.isLocked {
        Button {
          onPrune(worktree)
        } label: {
          WorktreeActionIcon(systemName: "eraser", pointSize: 14)
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .disabled(isRemovalInProgress)
        .help(L10n.string("action.prune_registration.help"))
        .accessibilityLabel(L10n.string("action.prune_registration"))
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
    VStack(alignment: .leading, spacing: 2) {
      Label(presentation.title, systemImage: presentation.systemImage)
        .font(.callout.weight(.medium))
        .foregroundStyle(presentation.tint)
        .lineLimit(1)

      if let detail = presentation.detail {
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .padding(.leading, 21)
      }
    }
    .help(presentation.help)
  }

  private var presentation: RecommendationPresentation {
    switch recommendation {
    case .protectedMainWorktree:
      RecommendationPresentation(
        title: L10n.string("recommendation.keep_main"),
        detail: nil,
        systemImage: "shield.fill",
        tint: .secondary
      )
    case .blocked(let reasons):
      blockedPresentation(reasons)
    case .needsReview(let reason):
      reviewPresentation(reason)
    case .cleanable(let target):
      RecommendationPresentation(
        title: L10n.format("recommendation.cleanable", target),
        detail: L10n.string("recommendation.cleanable.detail"),
        systemImage: "trash.circle.fill",
        tint: .green
      )
    }
  }

  private func blockedPresentation(_ reasons: [CleanupBlocker]) -> RecommendationPresentation {
    if reasons.contains(where: {
      if case .missing = $0 { true } else { false }
    }) {
      if reasons.contains(where: {
        if case .locked = $0 { true } else { false }
      }) {
        return RecommendationPresentation(
          title: L10n.string("recommendation.missing_path_locked"),
          detail: L10n.string("recommendation.missing_path_locked.detail"),
          systemImage: "lock.fill",
          tint: .orange
        )
      }
      return RecommendationPresentation(
        title: L10n.string("recommendation.missing_path"),
        detail: L10n.string("recommendation.missing_path.detail"),
        systemImage: "eraser.fill",
        tint: .green
      )
    }
    if reasons.contains(.uncommittedChanges) {
      return RecommendationPresentation(
        title: L10n.string("recommendation.uncommitted"),
        detail: L10n.string("recommendation.uncommitted.detail"),
        systemImage: "xmark.octagon.fill",
        tint: .red
      )
    }
    if case .locked(let reason) = reasons.first {
      return RecommendationPresentation(
        title: L10n.string("recommendation.locked"),
        detail: reason.map { L10n.format("recommendation.locked_reason", $0) }
          ?? L10n.string("recommendation.locked.detail"),
        systemImage: "lock.fill",
        tint: .orange
      )
    }
    return RecommendationPresentation(
      title: L10n.string("recommendation.blocked"),
      detail: nil,
      systemImage: "xmark.octagon.fill",
      tint: .red
    )
  }

  private func reviewPresentation(_ reason: CleanupReviewReason) -> RecommendationPresentation {
    switch reason {
    case .cleanupTargetUnavailable:
      RecommendationPresentation(
        title: L10n.string("recommendation.cleanup_target_unavailable"),
        detail: L10n.string("recommendation.cleanup_target_unavailable.detail"),
        systemImage: "questionmark.circle.fill",
        tint: .orange
      )
    case .notMerged(let target):
      RecommendationPresentation(
        title: L10n.format("recommendation.not_merged", target),
        detail: L10n.string("recommendation.not_merged.detail"),
        systemImage: "exclamationmark.triangle.fill",
        tint: .orange
      )
    case .detachedHeadNotMerged(let target):
      RecommendationPresentation(
        title: L10n.format("recommendation.detached_not_merged", target),
        detail: L10n.string("recommendation.detached_not_merged.detail"),
        systemImage: "xmark.octagon.fill",
        tint: .red
      )
    }
  }
}

private struct RecommendationPresentation {
  let title: String
  let detail: String?
  let systemImage: String
  let tint: Color

  var help: String {
    [title, detail].compactMap { $0 }.joined(separator: ". ")
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
