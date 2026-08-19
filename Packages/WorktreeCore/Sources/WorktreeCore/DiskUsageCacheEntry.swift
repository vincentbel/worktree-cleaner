import Foundation

public struct DiskUsageCacheEntry: Codable, Equatable, Sendable {
  public static let reuseInterval: TimeInterval = 7 * 24 * 60 * 60

  public let repositoryID: GitRepository.ID
  public let measuredAt: Date
  public let worktreeAllocatedBytes: [URL: Int64]
  public let sharedGitAllocatedBytes: Int64

  public var totalAllocatedBytes: Int64 {
    worktreeAllocatedBytes.values.reduce(sharedGitAllocatedBytes, +)
  }

  public init(
    repositoryID: GitRepository.ID,
    measuredAt: Date,
    worktreeAllocatedBytes: [URL: Int64],
    sharedGitAllocatedBytes: Int64
  ) {
    self.repositoryID = repositoryID
    self.measuredAt = measuredAt
    self.worktreeAllocatedBytes = worktreeAllocatedBytes
    self.sharedGitAllocatedBytes = sharedGitAllocatedBytes
  }

  public func isReusable(
    for snapshot: RepositorySnapshot,
    at date: Date = Date()
  ) -> Bool {
    guard repositoryID == snapshot.repository.id,
      date.timeIntervalSince(measuredAt) <= Self.reuseInterval
    else {
      return false
    }

    let measuredPaths = Set(worktreeAllocatedBytes.keys)
    let currentPaths = Set(
      snapshot.worktrees.lazy
        .filter { !$0.isPrunable }
        .map(\.path)
    )
    return currentPaths.isSubset(of: measuredPaths)
  }
}
