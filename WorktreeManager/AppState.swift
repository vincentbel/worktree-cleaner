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
  var isScanning = false
  var isLoadingSnapshot = false
  var isMeasuringDiskUsage = false
  var removingWorktreeID: GitWorktree.ID?
  var errorMessage: String?
  var successMessage: String?

  private let workspace: GitWorkspace
  private let defaults: UserDefaults
  private var didRestore = false
  private var activeScanID: UUID?
  private var activeSnapshotLoadID: UUID?
  private var diskUsageTask: Task<Void, Never>?

  init(
    workspace: GitWorkspace = GitWorkspace(),
    defaults: UserDefaults = .standard
  ) {
    self.workspace = workspace
    self.defaults = defaults
  }

  func restoreSelectedDirectory() async {
    guard !didRestore else { return }
    didRestore = true
    guard let path = defaults.string(forKey: Self.baseDirectoryKey) else { return }

    baseDirectoryURL = URL(filePath: path, directoryHint: .isDirectory)
    await scan()
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
    repositories = []
    selectedRepositoryID = nil
    snapshot = nil
    worktreeAllocatedBytes = [:]
    sharedGitAllocatedBytes = nil
    isLoadingSnapshot = false
    isMeasuringDiskUsage = false
    await scan()
  }

  func scan() async {
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
      if !repositories.contains(where: { $0.id == selectedRepositoryID }) {
        selectedRepositoryID = repositories.first?.id
        startedInitialLoad = false
      }
      if !startedInitialLoad {
        await loadSelectedRepository()
      }
    } catch {
      guard activeScanID == scanID else { return }
      errorMessage = error.localizedDescription
    }
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
      isLoadingSnapshot = false
      isMeasuringDiskUsage = false
      return
    }

    let loadID = UUID()
    activeSnapshotLoadID = loadID
    diskUsageTask?.cancel()
    worktreeAllocatedBytes = [:]
    sharedGitAllocatedBytes = nil
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
      snapshot = loadedSnapshot
      startMeasuringDiskUsage(for: loadedSnapshot, loadID: loadID)
    } catch {
      guard activeSnapshotLoadID == loadID else { return }
      errorMessage = error.localizedDescription
    }
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
      snapshot = loadedSnapshot
      worktreeAllocatedBytes = [:]
      sharedGitAllocatedBytes = nil
      startMeasuringDiskUsage(for: loadedSnapshot, loadID: loadID)
      if let branch = worktree.branch {
        successMessage =
          "已删除 \(worktree.path.lastPathComponent)，分支 \(branch) 仍然保留。"
      } else {
        successMessage = "已删除 \(worktree.path.lastPathComponent)。原 worktree 为 Detached HEAD。"
      }
    } catch {
      guard activeSnapshotLoadID == loadID else { return }
      errorMessage = error.localizedDescription
    }
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
        for try await update in workspace.diskUsage(of: snapshot) {
          guard activeSnapshotLoadID == loadID else { return }
          switch update {
          case .worktree(let path, let allocatedBytes):
            worktreeAllocatedBytes[path] = allocatedBytes
          case .sharedGit(let allocatedBytes):
            sharedGitAllocatedBytes = allocatedBytes
          }
        }
      } catch is CancellationError {
        return
      } catch {
        guard activeSnapshotLoadID == loadID else { return }
        errorMessage = error.localizedDescription
      }
    }
  }
}
