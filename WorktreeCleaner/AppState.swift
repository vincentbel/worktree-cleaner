import Foundation
import Observation
import WorktreeCore

struct BatchRemovalProgress: Equatable {
  let currentCount: Int
  let totalCount: Int
}

@MainActor
@Observable
final class AppState {
  private static let baseDirectoryPathsKey = "baseDirectoryPaths"

  var workspaceRoots = WorkspaceRoots()
  var selectedRootID: URL?
  var selectedRepositoryID: GitRepository.ID?
  var snapshot: RepositorySnapshot?
  var worktreeAllocatedBytes: [URL: Int64] = [:]
  var sharedGitAllocatedBytes: Int64?
  var diskUsageMeasuredAt: Date?
  var isLoadingSnapshot = false
  var isMeasuringDiskUsage = false
  var removingWorktreeID: GitWorktree.ID?
  var batchRemovalProgress: BatchRemovalProgress?
  var errorMessage: String?
  var successMessage: String?
  var transientMessage: String?

  var repositories: [GitRepository] {
    sortedRepositories(repositoryCatalog.repositories)
  }

  var visibleRepositories: [GitRepository] {
    let repositories =
      selectedRootID.map {
        repositoryCatalog.repositories(under: $0)
      } ?? repositoryCatalog.repositories
    return sortedRepositories(repositories)
  }

  var isScanning: Bool {
    !scanningRootIDs.isEmpty
  }

  var isScanningCurrentScope: Bool {
    selectedRootID.map { scanningRootIDs.contains($0) } ?? isScanning
  }

  private let workspace: GitWorkspace
  private let defaults: UserDefaults
  private let cacheStore: WorkspaceCacheStore
  private let scanLimiter = ScanLimiter(limit: 2)
  private var didRestore = false
  private var repositoryCatalog = RepositoryCatalog()
  private var scanningRootIDs: Set<URL> = []
  private var rootScanErrors: [URL: String] = [:]
  private var activeRootScanIDs: [URL: UUID] = [:]
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
    restoreWorkspaceRoots()
    guard !workspaceRoots.urls.isEmpty else { return }

    let restoredCache = cacheStore.load(configuredRootURLs: workspaceRoots.urls)
    if let restoredCache {
      repositoryCatalog = RepositoryCatalog(
        repositories: restoredCache.repositories,
        associations: restoredCache.associations
      )
      selectedRootID = restoredCache.selectedRootID
      for entry in restoredCache.diskUsageEntries {
        diskUsageCache[entry.repositoryID] = entry
      }
      if let repositoryID = restoredCache.selectedRepositoryID,
        repositoryCatalog.contains(repositoryID: repositoryID, under: selectedRootID)
      {
        selectedRepositoryID = restoredCache.selectedRepositoryID
      } else {
        selectedRepositoryID = visibleRepositories.first?.id
      }
      if selectedRepositoryID != nil {
        Task { await loadSelectedRepository() }
      }
    }
    await scanRoots(
      workspaceRoots.urls,
      refreshSelectedRepository: restoredCache == nil
    )
  }

  func addDirectory(_ url: URL) async {
    let selectedURL = WorkspaceRoots.normalize(url)
    do {
      try workspaceRoots.add(selectedURL)
    } catch let error as WorkspaceRootError {
      errorMessage = workspaceRootErrorMessage(error)
      return
    } catch {
      errorMessage = error.localizedDescription
      return
    }

    persistWorkspaceRoots()
    selectedRootID = selectedURL
    activeSnapshotLoadID = nil
    diskUsageTask?.cancel()
    selectedRepositoryID = nil
    snapshot = nil
    worktreeAllocatedBytes = [:]
    sharedGitAllocatedBytes = nil
    diskUsageMeasuredAt = nil
    isLoadingSnapshot = false
    isMeasuringDiskUsage = false
    persistWorkspaceCache()
    await scanRoots([selectedURL], refreshSelectedRepository: false)
  }

  func removeDirectory(_ url: URL) async {
    let rootID = WorkspaceRoots.normalize(url)
    guard workspaceRoots.urls.contains(rootID) else { return }

    activeRootScanIDs[rootID] = nil
    scanningRootIDs.remove(rootID)
    rootScanErrors[rootID] = nil
    workspaceRoots.remove(rootID)
    persistWorkspaceRoots()

    let removedRepositoryIDs = repositoryCatalog.reconcile(
      root: rootID,
      discoveredRepositoryIDs: []
    )
    removeCachedRepositoryState(for: removedRepositoryIDs)
    if selectedRootID == rootID {
      selectedRootID = nil
    }
    let selectionChanged = ensureValidSelection()
    persistWorkspaceCache()
    if selectionChanged || selectedRepositoryID == nil {
      await loadSelectedRepository()
    }
  }

  func selectRoot(_ rootID: URL?) async {
    guard selectedRootID != rootID else { return }
    selectedRootID = rootID
    let selectionChanged = ensureValidSelection()
    persistWorkspaceCache()
    if selectionChanged {
      await loadSelectedRepository()
    }
  }

  func scanSelectedScope() async {
    let rootURLs = selectedRootID.map { [$0] } ?? workspaceRoots.urls
    await scanRoots(rootURLs, refreshSelectedRepository: false)
  }

  func repositoryCount(under rootID: URL) -> Int {
    repositoryCatalog.repositories(under: rootID).count
  }

  func isScanning(_ rootID: URL) -> Bool {
    scanningRootIDs.contains(rootID)
  }

  func scanError(for rootID: URL) -> String? {
    rootScanErrors[rootID]
  }

  func measuredTotalAllocatedBytes(
    for repositoryID: GitRepository.ID
  ) -> Int64? {
    diskUsageCache[repositoryID]?.totalAllocatedBytes
  }

  private func scanRoot(_ rootID: URL) async -> Bool {
    let scanID = UUID()
    activeRootScanIDs[rootID] = scanID
    scanningRootIDs.insert(rootID)
    rootScanErrors[rootID] = nil
    defer {
      if activeRootScanIDs[rootID] == scanID {
        activeRootScanIDs[rootID] = nil
        scanningRootIDs.remove(rootID)
      }
    }

    do {
      var discoveredRepositoryIDs: Set<GitRepository.ID> = []
      var startedInitialLoad = false
      for try await repository in workspace.discover(in: rootID) {
        guard activeRootScanIDs[rootID] == scanID else { return false }
        discoveredRepositoryIDs.insert(repository.id)
        repositoryCatalog.register(repository, foundUnder: rootID)

        if selectedRepositoryID == nil,
          selectedRootID == nil || selectedRootID == rootID
        {
          selectedRepositoryID = repository.id
          startedInitialLoad = true
          Task { await loadSelectedRepository() }
        }
      }

      guard activeRootScanIDs[rootID] == scanID else { return false }
      let removedRepositoryIDs = repositoryCatalog.reconcile(
        root: rootID,
        discoveredRepositoryIDs: discoveredRepositoryIDs
      )
      removeCachedRepositoryState(for: removedRepositoryIDs)
      persistWorkspaceCache()
      return startedInitialLoad
    } catch {
      guard activeRootScanIDs[rootID] == scanID else { return false }
      rootScanErrors[rootID] = error.localizedDescription
      return false
    }
  }

  private func scanRoots(
    _ rootURLs: [URL],
    refreshSelectedRepository: Bool
  ) async {
    let configuredRootIDs = Set(workspaceRoots.urls)
    let rootURLs = rootURLs.filter { configuredRootIDs.contains($0) }
    guard !rootURLs.isEmpty else { return }

    var startedInitialLoad = false
    await withTaskGroup(of: Bool.self) { group in
      for rootURL in rootURLs {
        group.addTask {
          await self.scanLimiter.acquire()
          let didStartInitialLoad = await self.scanRoot(rootURL)
          await self.scanLimiter.release()
          return didStartInitialLoad
        }
      }
      while let didStartInitialLoad = await group.next() {
        startedInitialLoad = startedInitialLoad || didStartInitialLoad
      }
    }

    let selectionChanged = ensureValidSelection()
    persistWorkspaceCache()
    if selectionChanged || refreshSelectedRepository && !startedInitialLoad {
      await loadSelectedRepository()
    }
  }

  private func restoreWorkspaceRoots() {
    let paths = defaults.stringArray(forKey: Self.baseDirectoryPathsKey) ?? []

    var restoredRoots = WorkspaceRoots()
    for path in paths {
      do {
        try restoredRoots.add(URL(filePath: path, directoryHint: .isDirectory))
      } catch let error as WorkspaceRootError {
        errorMessage = workspaceRootErrorMessage(error)
      } catch {
        errorMessage = error.localizedDescription
      }
    }
    workspaceRoots = restoredRoots
    persistWorkspaceRoots()
  }

  private func persistWorkspaceRoots() {
    defaults.set(
      workspaceRoots.urls.map(\.path),
      forKey: Self.baseDirectoryPathsKey
    )
  }

  private func ensureValidSelection() -> Bool {
    if let selectedRepositoryID,
      repositoryCatalog.contains(repositoryID: selectedRepositoryID, under: selectedRootID)
    {
      return false
    }
    let previousRepositoryID = selectedRepositoryID
    selectedRepositoryID = visibleRepositories.first?.id
    return selectedRepositoryID != previousRepositoryID
  }

  private func removeCachedRepositoryState(
    for repositoryIDs: Set<GitRepository.ID>
  ) {
    for repositoryID in repositoryIDs {
      snapshotsByRepositoryID[repositoryID] = nil
      diskUsageCache[repositoryID] = nil
    }
  }

  private func sortedRepositories(_ repositories: [GitRepository]) -> [GitRepository] {
    repositories.sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }

  private func workspaceRootErrorMessage(_ error: WorkspaceRootError) -> String {
    switch error {
    case .duplicate(let existingURL):
      L10n.format("error.directory_duplicate", existingURL.path)
    case .overlaps(let existingURL):
      L10n.format("error.directory_overlap", existingURL.path)
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
      let repository = repositoryCatalog.repositories.first(where: {
        $0.id == selectedRepositoryID
      })
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
      removingWorktreeID == nil,
      batchRemovalProgress == nil
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

  func removeAll(_ worktrees: [GitWorktree]) async {
    guard let currentSnapshot = snapshot,
      removingWorktreeID == nil,
      batchRemovalProgress == nil
    else { return }

    let requestedIDs = Set(worktrees.map(\.id))
    let candidates = currentSnapshot.worktrees.filter { worktree in
      guard requestedIDs.contains(worktree.id) else { return false }
      switch worktree.cleanupRecommendation {
      case .cleanable, .needsReview(reason: .notMerged):
        return true
      default:
        return false
      }
    }
    guard !candidates.isEmpty else { return }

    let repository = currentSnapshot.repository
    let loadID = UUID()
    activeSnapshotLoadID = loadID
    diskUsageTask?.cancel()
    isMeasuringDiskUsage = false
    isLoadingSnapshot = true
    batchRemovalProgress = BatchRemovalProgress(
      currentCount: 1,
      totalCount: candidates.count
    )
    errorMessage = nil
    successMessage = nil
    defer {
      if activeSnapshotLoadID == loadID {
        isLoadingSnapshot = false
      }
      removingWorktreeID = nil
      batchRemovalProgress = nil
    }

    var removedCount = 0
    var failures: [String] = []

    for (index, worktree) in candidates.enumerated() {
      batchRemovalProgress = BatchRemovalProgress(
        currentCount: index + 1,
        totalCount: candidates.count
      )
      removingWorktreeID = worktree.id
      do {
        _ = try await workspace.remove(
          worktree,
          from: repository,
          policy: .allowUnmerged
        )
        removedCount += 1
      } catch {
        let label = worktree.branch ?? worktree.path.lastPathComponent
        failures.append(L10n.format("batch.result.failure", label, error.localizedDescription))
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
      diskUsageCache[repository.id] = nil
      worktreeAllocatedBytes = [:]
      sharedGitAllocatedBytes = nil
      diskUsageMeasuredAt = nil
      persistWorkspaceCache()
      startMeasuringDiskUsage(for: loadedSnapshot, loadID: loadID)

      let removedSummary = L10n.plural("batch.result.removed", count: removedCount)
      if failures.isEmpty {
        successMessage = L10n.format("batch.result.success", removedSummary)
      } else {
        let skippedSummary = L10n.plural("batch.result.skipped", count: failures.count)
        successMessage = L10n.format(
          "batch.result.partial",
          removedSummary,
          skippedSummary,
          failures.joined(separator: "\n")
        )
      }
    } catch {
      guard activeSnapshotLoadID == loadID else { return }
      errorMessage = error.localizedDescription
    }
  }

  func prune(_ worktree: GitWorktree) async {
    guard let repository = snapshot?.repository,
      removingWorktreeID == nil,
      batchRemovalProgress == nil
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
      let loadedSnapshot = try await workspace.prune(worktree, from: repository)
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
      successMessage = L10n.string("success.pruned_registrations")
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
    repositoryCatalog.update(repository)
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
    cacheStore.save(
      WorkspaceCache(
        repositories: repositoryCatalog.repositories,
        associations: repositoryCatalog.associations,
        selectedRootID: selectedRootID,
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

private actor ScanLimiter {
  private var availablePermits: Int
  private var waiters: [CheckedContinuation<Void, Never>] = []

  init(limit: Int) {
    availablePermits = limit
  }

  func acquire() async {
    if availablePermits > 0 {
      availablePermits -= 1
      return
    }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func release() {
    if waiters.isEmpty {
      availablePermits += 1
    } else {
      waiters.removeFirst().resume()
    }
  }
}
