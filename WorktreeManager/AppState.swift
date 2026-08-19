import Foundation
import Observation
import WorktreeCore

@MainActor
@Observable
final class AppState {
  private static let baseDirectoryKey = "baseDirectoryPath"

  var baseDirectoryURL: URL?
  var repositories: [GitRepository] = []
  var selectedRepositoryID: GitRepository.ID?
  var snapshot: RepositorySnapshot?
  var worktreeAllocatedBytes: [URL: Int64] = [:]
  var sharedGitAllocatedBytes: Int64?
  var diskUsageMeasuredAt: Date?
  var isScanning = false
  var isLoadingSnapshot = false
  var isMeasuringDiskUsage = false
  var removingWorktreeID: GitWorktree.ID?
  var errorMessage: String?
  var successMessage: String?
  var transientMessage: String?

  private let workspace: GitWorkspace
  private let defaults: UserDefaults
  private let cacheStore: WorkspaceCacheStore
  private var didRestore = false
  private var activeScanID: UUID?
  private var activeSnapshotLoadID: UUID?
  private var diskUsageTask: Task<Void, Never>?
  private var transientMessageTask: Task<Void, Never>?
  private var snapshotsByRepositoryID: [GitRepository.ID: RepositorySnapshot] = [:]
  private var diskUsageCache: [GitRepository.ID: DiskUsageCacheEntry] = [:]

  init(
    workspace: GitWorkspace = GitWorkspace(),
    defaults: UserDefaults = .standard
  ) {
    self.workspace = workspace
    self.defaults = defaults
    self.cacheStore = WorkspaceCacheStore(defaults: defaults)
  }

  func restoreSelectedDirectory() async {
    guard !didRestore else { return }
    didRestore = true
    guard let path = defaults.string(forKey: Self.baseDirectoryKey) else { return }

    let restoredDirectoryURL = URL(filePath: path, directoryHint: .isDirectory)
    baseDirectoryURL = restoredDirectoryURL
    let restoredCache = cacheStore.load(for: restoredDirectoryURL)
    if let restoredCache {
      repositories = restoredCache.repositories.sorted {
        $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
      for entry in restoredCache.diskUsageEntries {
        diskUsageCache[entry.repositoryID] = entry
      }
      if repositories.contains(where: { $0.id == restoredCache.selectedRepositoryID }) {
        selectedRepositoryID = restoredCache.selectedRepositoryID
      } else {
        selectedRepositoryID = repositories.first?.id
      }
      if selectedRepositoryID != nil {
        Task { await loadSelectedRepository() }
      }
    }
    await scan(refreshSelectedRepository: restoredCache == nil)
  }

  func chooseDirectory(_ url: URL) async {
    let selectedURL = URL(
      filePath: url.standardizedFileURL.path,
      directoryHint: .isDirectory
    )
    baseDirectoryURL = selectedURL
    defaults.set(selectedURL.path, forKey: Self.baseDirectoryKey)
    activeScanID = nil
    activeSnapshotLoadID = nil
    diskUsageTask?.cancel()
    cacheStore.remove()
    transientMessageTask?.cancel()
    repositories = []
    selectedRepositoryID = nil
    snapshot = nil
    snapshotsByRepositoryID = [:]
    diskUsageCache = [:]
    worktreeAllocatedBytes = [:]
    sharedGitAllocatedBytes = nil
    diskUsageMeasuredAt = nil
    isLoadingSnapshot = false
    isMeasuringDiskUsage = false
    transientMessage = nil
    await scan()
  }

  func scan(refreshSelectedRepository: Bool = true) async {
    guard let baseDirectoryURL else { return }

    let scanID = UUID()
    activeScanID = scanID
    isScanning = true
    defer {
      if activeScanID == scanID {
        activeScanID = nil
        isScanning = false
      }
    }

    do {
      var discoveredRepositoryIDs: Set<GitRepository.ID> = []
      var startedInitialLoad = false
      for try await repository in workspace.discover(in: baseDirectoryURL) {
        guard activeScanID == scanID else { return }
        discoveredRepositoryIDs.insert(repository.id)
        if let index = repositories.firstIndex(where: { $0.id == repository.id }) {
          repositories[index] = repository
        } else {
          repositories.append(repository)
        }
        repositories.sort {
          $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        if selectedRepositoryID == nil {
          selectedRepositoryID = repository.id
          startedInitialLoad = true
          Task { await loadSelectedRepository() }
        }
      }

      guard activeScanID == scanID else { return }
      repositories.removeAll { !discoveredRepositoryIDs.contains($0.id) }
      var selectionChanged = false
      if !repositories.contains(where: { $0.id == selectedRepositoryID }) {
        selectedRepositoryID = repositories.first?.id
        startedInitialLoad = false
        selectionChanged = true
      }
      persistWorkspaceCache()
      if !startedInitialLoad, refreshSelectedRepository || selectionChanged {
        await loadSelectedRepository()
      }
    } catch {
      guard activeScanID == scanID else { return }
      errorMessage = error.localizedDescription
    }
  }

  func selectRepository(_ repositoryID: GitRepository.ID?) async {
    guard selectedRepositoryID != repositoryID else { return }
    selectedRepositoryID = repositoryID
    persistWorkspaceCache()
    await loadSelectedRepository()
  }

  func loadSelectedRepository() async {
    guard
      let selectedRepositoryID,
      let repository = repositories.first(where: { $0.id == selectedRepositoryID })
    else {
      activeSnapshotLoadID = nil
      snapshot = nil
      diskUsageTask?.cancel()
      worktreeAllocatedBytes = [:]
      sharedGitAllocatedBytes = nil
      diskUsageMeasuredAt = nil
      isLoadingSnapshot = false
      isMeasuringDiskUsage = false
      return
    }

    let loadID = UUID()
    activeSnapshotLoadID = loadID
    diskUsageTask?.cancel()
    snapshot = snapshotsByRepositoryID[selectedRepositoryID]
    applyCachedDiskUsage(for: selectedRepositoryID)
    isMeasuringDiskUsage = false
    isLoadingSnapshot = true
    defer {
      if activeSnapshotLoadID == loadID {
        isLoadingSnapshot = false
      }
    }

    do {
      let loadedSnapshot = try await workspace.snapshot(of: repository)
      guard activeSnapshotLoadID == loadID,
        selectedRepositoryID == repository.id
      else { return }
      updateRepository(loadedSnapshot.repository)
      snapshotsByRepositoryID[repository.id] = loadedSnapshot
      snapshot = loadedSnapshot
      applyCachedDiskUsage(for: repository.id)
      persistWorkspaceCache()
      if diskUsageCache[repository.id]?.isReusable(for: loadedSnapshot) != true {
        startMeasuringDiskUsage(for: loadedSnapshot, loadID: loadID)
      }
    } catch {
      guard activeSnapshotLoadID == loadID else { return }
      errorMessage = error.localizedDescription
    }
  }

  func recalculateDiskUsage() {
    guard let snapshot,
      snapshot.repository.id == selectedRepositoryID,
      !isLoadingSnapshot,
      !isMeasuringDiskUsage
    else {
      return
    }

    let loadID = UUID()
    activeSnapshotLoadID = loadID
    diskUsageTask?.cancel()
    startMeasuringDiskUsage(for: snapshot, loadID: loadID)
  }

  func remove(_ worktree: GitWorktree) async {
    guard let repository = snapshot?.repository,
      removingWorktreeID == nil
    else { return }

    let loadID = UUID()
    activeSnapshotLoadID = loadID
    diskUsageTask?.cancel()
    isMeasuringDiskUsage = false
    isLoadingSnapshot = true
    removingWorktreeID = worktree.id
    errorMessage = nil
    successMessage = nil
    defer {
      if activeSnapshotLoadID == loadID {
        isLoadingSnapshot = false
      }
      if removingWorktreeID == worktree.id {
        removingWorktreeID = nil
      }
    }

    do {
      let loadedSnapshot = try await workspace.remove(worktree, from: repository)
      guard activeSnapshotLoadID == loadID,
        selectedRepositoryID == repository.id
      else { return }
      updateRepository(loadedSnapshot.repository)
      snapshotsByRepositoryID[repository.id] = loadedSnapshot
      snapshot = loadedSnapshot
      diskUsageCache[repository.id] = nil
      worktreeAllocatedBytes = [:]
      sharedGitAllocatedBytes = nil
      diskUsageMeasuredAt = nil
      persistWorkspaceCache()
      startMeasuringDiskUsage(for: loadedSnapshot, loadID: loadID)
      if let branch = worktree.branch {
        successMessage = L10n.format(
          "success.removed_branch",
          worktree.path.lastPathComponent,
          branch
        )
      } else {
        successMessage = L10n.format(
          "success.removed_detached",
          worktree.path.lastPathComponent
        )
      }
    } catch {
      guard activeSnapshotLoadID == loadID else { return }
      errorMessage = error.localizedDescription
    }
  }

  func showTransientMessage(_ message: String) {
    transientMessageTask?.cancel()
    transientMessage = message
    transientMessageTask = Task {
      do {
        try await Task.sleep(for: .seconds(1.5))
      } catch {
        return
      }
      guard transientMessage == message else { return }
      transientMessage = nil
    }
  }

  private func updateRepository(_ repository: GitRepository) {
    guard let index = repositories.firstIndex(where: { $0.id == repository.id }) else {
      return
    }
    repositories[index] = repository
  }

  private func applyCachedDiskUsage(for repositoryID: GitRepository.ID) {
    guard let cache = diskUsageCache[repositoryID] else {
      worktreeAllocatedBytes = [:]
      sharedGitAllocatedBytes = nil
      diskUsageMeasuredAt = nil
      return
    }
    worktreeAllocatedBytes = cache.worktreeAllocatedBytes
    sharedGitAllocatedBytes = cache.sharedGitAllocatedBytes
    diskUsageMeasuredAt = cache.measuredAt
  }

  private func persistWorkspaceCache() {
    guard let baseDirectoryURL else { return }
    cacheStore.save(
      WorkspaceCache(
        baseDirectoryURL: baseDirectoryURL,
        repositories: repositories,
        selectedRepositoryID: selectedRepositoryID,
        diskUsageEntries: Array(diskUsageCache.values)
      )
    )
  }

  private func startMeasuringDiskUsage(
    for snapshot: RepositorySnapshot,
    loadID: UUID
  ) {
    diskUsageTask = Task {
      isMeasuringDiskUsage = true
      defer {
        if activeSnapshotLoadID == loadID {
          isMeasuringDiskUsage = false
        }
      }

      do {
        var measuredWorktrees: [URL: Int64] = [:]
        var measuredSharedGit: Int64?
        for try await update in workspace.diskUsage(of: snapshot) {
          guard activeSnapshotLoadID == loadID else { return }
          switch update {
          case .worktree(let path, let allocatedBytes):
            measuredWorktrees[path] = allocatedBytes
            worktreeAllocatedBytes[path] = allocatedBytes
          case .sharedGit(let allocatedBytes):
            measuredSharedGit = allocatedBytes
            sharedGitAllocatedBytes = allocatedBytes
          }
        }
        guard activeSnapshotLoadID == loadID,
          let measuredSharedGit
        else {
          return
        }
        let cache = DiskUsageCacheEntry(
          repositoryID: snapshot.repository.id,
          measuredAt: Date(),
          worktreeAllocatedBytes: measuredWorktrees,
          sharedGitAllocatedBytes: measuredSharedGit
        )
        diskUsageCache[snapshot.repository.id] = cache
        worktreeAllocatedBytes = measuredWorktrees
        sharedGitAllocatedBytes = measuredSharedGit
        diskUsageMeasuredAt = cache.measuredAt
        persistWorkspaceCache()
      } catch is CancellationError {
        return
      } catch {
        guard activeSnapshotLoadID == loadID else { return }
        errorMessage = error.localizedDescription
      }
    }
  }
}
