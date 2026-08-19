import Foundation

public struct RepositorySnapshot: Equatable, Sendable {
  public let repository: GitRepository
  public let worktrees: [GitWorktree]
}

public struct GitWorktree: Identifiable, Equatable, Sendable {
  public var id: URL { path }

  public let path: URL
  public let head: String
  public let branch: String?
  public let isDetached: Bool
  public let isMain: Bool
  public let isLocked: Bool
  public let lockReason: String?
  public let status: WorktreeStatus
  public let cleanupRecommendation: CleanupRecommendation

  init(
    path: URL,
    head: String,
    branch: String?,
    isDetached: Bool,
    isMain: Bool,
    isLocked: Bool,
    lockReason: String?,
    status: WorktreeStatus,
    cleanupRecommendation: CleanupRecommendation
  ) {
    self.path = path
    self.head = head
    self.branch = branch
    self.isDetached = isDetached
    self.isMain = isMain
    self.isLocked = isLocked
    self.lockReason = lockReason
    self.status = status
    self.cleanupRecommendation = cleanupRecommendation
  }
}

public enum CleanupRecommendation: Equatable, Sendable {
  case protectedMainWorktree
  case blocked(reasons: [CleanupBlocker])
  case needsReview(reason: CleanupReviewReason)
  case cleanable(target: String)
}

public enum CleanupBlocker: Equatable, Sendable {
  case locked(reason: String?)
  case uncommittedChanges
}

public enum CleanupReviewReason: Equatable, Sendable {
  case cleanupTargetUnavailable
  case notMerged(target: String)
}

public struct WorktreeStatus: Equatable, Sendable {
  public var isClean: Bool {
    stagedFileCount == 0
      && modifiedFileCount == 0
      && untrackedFileCount == 0
      && conflictedFileCount == 0
  }

  public let stagedFileCount: Int
  public let modifiedFileCount: Int
  public let untrackedFileCount: Int
  public let conflictedFileCount: Int

  init(
    stagedFileCount: Int,
    modifiedFileCount: Int,
    untrackedFileCount: Int,
    conflictedFileCount: Int
  ) {
    self.stagedFileCount = stagedFileCount
    self.modifiedFileCount = modifiedFileCount
    self.untrackedFileCount = untrackedFileCount
    self.conflictedFileCount = conflictedFileCount
  }
}
