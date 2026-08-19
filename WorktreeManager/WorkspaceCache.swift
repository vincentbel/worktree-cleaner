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

private struct LegacyWorkspaceCache: Codable, Sendable {
  let baseDirectoryURL: URL
  let repositories: [GitRepository]
  let selectedRepositoryID: GitRepository.ID?
  let diskUsageEntries: [DiskUsageCacheEntry]
}

struct WorkspaceCacheStore {
  private static let key = "workspaceCache.v2"
  private static let legacyKey = "workspaceCache.v1"

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

    return loadLegacyCache(configuredRootURLs: configuredRootURLs)
  }

  func save(_ cache: WorkspaceCache) {
    do {
      defaults.set(try JSONEncoder().encode(cache), forKey: Self.key)
      defaults.removeObject(forKey: Self.legacyKey)
    } catch {
      logger.error("Could not encode workspace cache: \(error.localizedDescription)")
    }
  }

  func remove() {
    defaults.removeObject(forKey: Self.key)
    defaults.removeObject(forKey: Self.legacyKey)
  }

  private func loadLegacyCache(configuredRootURLs: [URL]) -> WorkspaceCache? {
    guard let data = defaults.data(forKey: Self.legacyKey) else { return nil }
    do {
      let legacyCache = try JSONDecoder().decode(LegacyWorkspaceCache.self, from: data)
      let rootURL = WorkspaceRoots.normalize(legacyCache.baseDirectoryURL)
      guard configuredRootURLs.contains(rootURL) else { return nil }

      let cache = WorkspaceCache(
        repositories: legacyCache.repositories,
        associations: legacyCache.repositories.map {
          RepositoryRootAssociation(repositoryID: $0.id, rootIDs: [rootURL])
        },
        selectedRootID: nil,
        selectedRepositoryID: legacyCache.selectedRepositoryID,
        diskUsageEntries: legacyCache.diskUsageEntries
      ).filtered(to: configuredRootURLs)
      save(cache)
      return cache
    } catch {
      logger.error("Could not decode legacy workspace cache: \(error.localizedDescription)")
      defaults.removeObject(forKey: Self.legacyKey)
      return nil
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
