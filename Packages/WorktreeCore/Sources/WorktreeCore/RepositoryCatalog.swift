import Foundation

public struct RepositoryRootAssociation: Codable, Equatable, Sendable {
  public let repositoryID: GitRepository.ID
  public let rootIDs: [URL]

  public init(repositoryID: GitRepository.ID, rootIDs: [URL]) {
    self.repositoryID = repositoryID
    self.rootIDs = rootIDs
  }
}

public struct RepositoryCatalog: Sendable {
  private var repositoriesByID: [GitRepository.ID: GitRepository]
  private var rootIDsByRepositoryID: [GitRepository.ID: Set<URL>]

  public init(
    repositories: [GitRepository] = [],
    associations: [RepositoryRootAssociation] = []
  ) {
    self.repositoriesByID = Dictionary(
      uniqueKeysWithValues: repositories.map { ($0.id, $0) }
    )
    self.rootIDsByRepositoryID = [:]
    for association in associations where repositoriesByID[association.repositoryID] != nil {
      rootIDsByRepositoryID[association.repositoryID, default: []]
        .formUnion(association.rootIDs)
    }
  }

  public var repositories: [GitRepository] {
    Array(repositoriesByID.values)
  }

  public var associations: [RepositoryRootAssociation] {
    rootIDsByRepositoryID.map { repositoryID, rootIDs in
      RepositoryRootAssociation(
        repositoryID: repositoryID,
        rootIDs: rootIDs.sorted { $0.path < $1.path }
      )
    }
  }

  public mutating func register(
    _ repository: GitRepository,
    foundUnder rootID: URL
  ) {
    repositoriesByID[repository.id] = repository
    rootIDsByRepositoryID[repository.id, default: []].insert(rootID)
  }

  public mutating func update(_ repository: GitRepository) {
    guard repositoriesByID[repository.id] != nil else { return }
    repositoriesByID[repository.id] = repository
  }

  public func repositories(under rootID: URL) -> [GitRepository] {
    repositoriesByID.compactMap { repositoryID, repository in
      rootIDsByRepositoryID[repositoryID]?.contains(rootID) == true
        ? repository
        : nil
    }
  }

  public func contains(
    repositoryID: GitRepository.ID,
    under rootID: URL?
  ) -> Bool {
    guard repositoriesByID[repositoryID] != nil else { return false }
    guard let rootID else { return true }
    return rootIDsByRepositoryID[repositoryID]?.contains(rootID) == true
  }

  @discardableResult
  public mutating func reconcile(
    root rootID: URL,
    discoveredRepositoryIDs: Set<GitRepository.ID>
  ) -> Set<GitRepository.ID> {
    var removedRepositoryIDs: Set<GitRepository.ID> = []
    let previousRepositoryIDs = rootIDsByRepositoryID.compactMap { repositoryID, rootIDs in
      rootIDs.contains(rootID) ? repositoryID : nil
    }

    for repositoryID in previousRepositoryIDs where !discoveredRepositoryIDs.contains(repositoryID)
    {
      rootIDsByRepositoryID[repositoryID]?.remove(rootID)
      if rootIDsByRepositoryID[repositoryID]?.isEmpty == true {
        rootIDsByRepositoryID[repositoryID] = nil
        repositoriesByID[repositoryID] = nil
        removedRepositoryIDs.insert(repositoryID)
      }
    }
    return removedRepositoryIDs
  }
}
