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
  var isScanning = false
  var isLoadingSnapshot = false
  var errorMessage: String?

  private let workspace: GitWorkspace
  private let defaults: UserDefaults
  private var didRestore = false

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
    await scan()
  }

  func scan() async {
    guard let baseDirectoryURL else { return }

    isScanning = true
    defer { isScanning = false }

    do {
      let discoveredRepositories = try await workspace.discover(in: baseDirectoryURL)
      repositories = discoveredRepositories

      if !discoveredRepositories.contains(where: { $0.id == selectedRepositoryID }) {
        selectedRepositoryID = discoveredRepositories.first?.id
      }
      await loadSelectedRepository()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func loadSelectedRepository() async {
    guard
      let selectedRepositoryID,
      let repository = repositories.first(where: { $0.id == selectedRepositoryID })
    else {
      snapshot = nil
      return
    }

    isLoadingSnapshot = true
    defer { isLoadingSnapshot = false }

    do {
      let loadedSnapshot = try await workspace.snapshot(of: repository)
      guard self.selectedRepositoryID == repository.id else { return }
      snapshot = loadedSnapshot
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func remove(_ worktree: GitWorktree) async {
    guard let repository = snapshot?.repository else { return }

    isLoadingSnapshot = true
    defer { isLoadingSnapshot = false }

    do {
      snapshot = try await workspace.remove(worktree, from: repository)
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
