import Foundation
import XCTest

@testable import WorktreeCore

final class DiskUsageCacheEntryTests: XCTestCase {
  func testTotalAllocatedBytesIncludesWorktreesAndSharedGitData() {
    let snapshot = makeSnapshot()
    let entry = DiskUsageCacheEntry(
      repositoryID: snapshot.repository.id,
      measuredAt: Date(),
      worktreeAllocatedBytes: [
        snapshot.worktrees[0].path: 1_024,
        snapshot.worktrees[1].path: 2_048,
      ],
      sharedGitAllocatedBytes: 4_096
    )

    XCTAssertEqual(entry.totalAllocatedBytes, 7_168)
  }

  func testEntryIsReusableForSevenDaysWhenEveryCurrentWorktreeWasMeasured() {
    let snapshot = makeSnapshot()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let entry = DiskUsageCacheEntry(
      repositoryID: snapshot.repository.id,
      measuredAt: now.addingTimeInterval(-7 * 24 * 60 * 60),
      worktreeAllocatedBytes: Dictionary(
        uniqueKeysWithValues: snapshot.worktrees.map { ($0.path, 1_024) }
      ),
      sharedGitAllocatedBytes: 2_048
    )

    XCTAssertTrue(entry.isReusable(for: snapshot, at: now))
  }

  func testEntryExpiresAfterSevenDays() {
    let snapshot = makeSnapshot()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let entry = DiskUsageCacheEntry(
      repositoryID: snapshot.repository.id,
      measuredAt: now.addingTimeInterval(-(7 * 24 * 60 * 60 + 1)),
      worktreeAllocatedBytes: Dictionary(
        uniqueKeysWithValues: snapshot.worktrees.map { ($0.path, 1_024) }
      ),
      sharedGitAllocatedBytes: 2_048
    )

    XCTAssertFalse(entry.isReusable(for: snapshot, at: now))
  }

  func testEntryIsNotReusableWhenANewWorktreeHasNoMeasurement() {
    let snapshot = makeSnapshot()
    let entry = DiskUsageCacheEntry(
      repositoryID: snapshot.repository.id,
      measuredAt: Date(),
      worktreeAllocatedBytes: [snapshot.worktrees[0].path: 1_024],
      sharedGitAllocatedBytes: 2_048
    )

    XCTAssertFalse(entry.isReusable(for: snapshot, at: Date()))
  }

  func testRepositoryCanRoundTripThroughPersistentCacheData() throws {
    let repository = makeSnapshot().repository

    let data = try JSONEncoder().encode(repository)
    let decoded = try JSONDecoder().decode(GitRepository.self, from: data)

    XCTAssertEqual(decoded, repository)
  }

  func testDiskUsageEntryCanRoundTripThroughPersistentCacheData() throws {
    let snapshot = makeSnapshot()
    let entry = DiskUsageCacheEntry(
      repositoryID: snapshot.repository.id,
      measuredAt: Date(timeIntervalSince1970: 1_800_000_000),
      worktreeAllocatedBytes: Dictionary(
        uniqueKeysWithValues: snapshot.worktrees.map { ($0.path, 1_024) }
      ),
      sharedGitAllocatedBytes: 2_048
    )

    let data = try JSONEncoder().encode(entry)
    let decoded = try JSONDecoder().decode(DiskUsageCacheEntry.self, from: data)

    XCTAssertEqual(decoded, entry)
  }

  private func makeSnapshot() -> RepositorySnapshot {
    let repository = GitRepository(
      workingTreeURL: URL(filePath: "/tmp/project"),
      commonGitDirectoryURL: URL(filePath: "/tmp/project/.git"),
      linkedWorktreeCount: 1
    )
    let worktrees = [
      makeWorktree(path: "/tmp/project", isMain: true),
      makeWorktree(path: "/tmp/project-agent", isMain: false),
    ]
    return RepositorySnapshot(repository: repository, worktrees: worktrees)
  }

  private func makeWorktree(path: String, isMain: Bool) -> GitWorktree {
    GitWorktree(
      path: URL(filePath: path),
      head: "0123456789abcdef",
      branch: isMain ? "main" : "agent-task",
      isDetached: false,
      isMain: isMain,
      isLocked: false,
      lockReason: nil,
      isPrunable: false,
      prunableReason: nil,
      status: WorktreeStatus(
        stagedFileCount: 0,
        modifiedFileCount: 0,
        untrackedFileCount: 0,
        conflictedFileCount: 0
      ),
      cleanupRecommendation: isMain
        ? .protectedMainWorktree
        : .cleanable(target: "origin/main")
    )
  }
}
