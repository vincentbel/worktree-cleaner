import Foundation
import OSLog
import WorktreeCore

struct WorkspaceCache: Codable, Sendable {
  let repositories: [GitRepository]
  let associations: [RepositoryRootAssociation]
  let selectedRootID: URL?
  let selectedRepositoryID: GitRepository.ID?
  let diskUsageEntries: [DiskUsageCacheEntry]
}

struct WorkspaceCacheStore {
  private static let key = "workspaceCache"

  private let defaults: UserDefaults
  private let logger = Logger(
    subsystem: "dev.worktreemanager.app",
    category: "WorkspaceCache"
  )

  init(defaults: UserDefaults) {
    self.defaults = defaults
  }

  func load(configuredRootURLs: [URL]) -> WorkspaceCache? {
    if let data = defaults.data(forKey: Self.key) {
      do {
        let cache = try JSONDecoder().decode(WorkspaceCache.self, from: data)
        return cache.filtered(to: configuredRootURLs)
      } catch {
        logger.error("Could not decode workspace cache: \(error.localizedDescription)")
        defaults.removeObject(forKey: Self.key)
      }
    }

    return nil
  }

  func save(_ cache: WorkspaceCache) {
    do {
      defaults.set(try JSONEncoder().encode(cache), forKey: Self.key)
    } catch {
      logger.error("Could not encode workspace cache: \(error.localizedDescription)")
    }
  }
}

extension WorkspaceCache {
  fileprivate func filtered(to configuredRootURLs: [URL]) -> WorkspaceCache {
    let configuredRootIDs = Set(configuredRootURLs)
    let filteredAssociations: [RepositoryRootAssociation] = associations.compactMap {
      association in
      let rootIDs = association.rootIDs.filter { configuredRootIDs.contains($0) }
      guard !rootIDs.isEmpty else { return nil }
      return RepositoryRootAssociation(
        repositoryID: association.repositoryID,
        rootIDs: rootIDs
      )
    }
    let repositoryIDs = Set(filteredAssociations.map(\.repositoryID))
    let filteredRepositories = repositories.filter { repositoryIDs.contains($0.id) }
    let filteredSelectedRepositoryID = selectedRepositoryID.flatMap {
      repositoryIDs.contains($0) ? $0 : nil
    }

    return WorkspaceCache(
      repositories: filteredRepositories,
      associations: filteredAssociations,
      selectedRootID: selectedRootID.flatMap {
        configuredRootIDs.contains($0) ? $0 : nil
      },
      selectedRepositoryID: filteredSelectedRepositoryID,
      diskUsageEntries: diskUsageEntries.filter {
        repositoryIDs.contains($0.repositoryID)
      }
    )
  }
}
