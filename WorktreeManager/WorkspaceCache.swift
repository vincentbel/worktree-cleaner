import Foundation
import OSLog
import WorktreeCore

struct WorkspaceCache: Codable, Sendable {
  let baseDirectoryURL: URL
  let repositories: [GitRepository]
  let selectedRepositoryID: GitRepository.ID?
  let diskUsageEntries: [DiskUsageCacheEntry]
}

struct WorkspaceCacheStore {
  private static let key = "workspaceCache.v1"

  private let defaults: UserDefaults
  private let logger = Logger(
    subsystem: "dev.worktreemanager.app",
    category: "WorkspaceCache"
  )

  init(defaults: UserDefaults) {
    self.defaults = defaults
  }

  func load(for baseDirectoryURL: URL) -> WorkspaceCache? {
    guard let data = defaults.data(forKey: Self.key) else { return nil }
    do {
      let cache = try JSONDecoder().decode(WorkspaceCache.self, from: data)
      guard cache.baseDirectoryURL.standardizedFileURL == baseDirectoryURL.standardizedFileURL
      else {
        return nil
      }
      return cache
    } catch {
      logger.error("Could not decode workspace cache: \(error.localizedDescription)")
      defaults.removeObject(forKey: Self.key)
      return nil
    }
  }

  func save(_ cache: WorkspaceCache) {
    do {
      defaults.set(try JSONEncoder().encode(cache), forKey: Self.key)
    } catch {
      logger.error("Could not encode workspace cache: \(error.localizedDescription)")
    }
  }

  func remove() {
    defaults.removeObject(forKey: Self.key)
  }
}
