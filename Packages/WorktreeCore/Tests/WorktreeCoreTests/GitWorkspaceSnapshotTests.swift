import Foundation
import WorktreeCore
import XCTest

final class GitWorkspaceSnapshotTests: XCTestCase {
  func testSnapshotReportsHeadCommitterDateDespiteUncommittedEdits() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let date = "2024-02-03T04:05:06Z"
    try runGit(
      [
        "-c", "user.name=Worktree Cleaner Tests",
        "-c", "user.email=tests@example.com",
        "commit", "--quiet", "--allow-empty", "-m", "Dated commit",
      ],
      in: fixture.linkedWorktree,
      environment: ["GIT_AUTHOR_DATE": "2020-01-02T03:04:05Z", "GIT_COMMITTER_DATE": date]
    )
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.repository))
    let repository = try XCTUnwrap(repositories.first)
    let initial = try await workspace.snapshot(of: repository)
    let expectedDate = try XCTUnwrap(ISO8601DateFormatter().date(from: date))
    XCTAssertEqual(initial.worktrees.first { !$0.isMain }?.commitDate, expectedDate)
    try Data("new edits".utf8).write(to: fixture.linkedWorktree.appending(path: "notes.txt"))

    let updated = try await workspace.snapshot(of: repository)

    let linked = try XCTUnwrap(updated.worktrees.first { !$0.isMain })
    XCTAssertEqual(linked.commitDate, expectedDate)
    XCTAssertFalse(try XCTUnwrap(linked.status).isClean)
  }

  func testSnapshotKeepsKnownCommitDatesWhenAStaleHeadIsUnavailable() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let other = fixture.base.appending(path: "other-agent")
    try runGit(
      ["worktree", "add", "--quiet", "-b", "other-agent", other.path], in: fixture.repository)
    let gitFile = try String(contentsOf: other.appending(path: ".git"), encoding: .utf8)
    let gitDirectory = URL(
      filePath: String(gitFile.dropFirst("gitdir: ".count)).trimmingCharacters(in: .newlines))
    try FileManager.default.removeItem(at: fixture.linkedWorktree)
    try FileManager.default.removeItem(at: other)
    try Data((String(repeating: "f", count: 40) + "\n").utf8)
      .write(to: gitDirectory.appending(path: "HEAD"))
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.repository))
    let repository = try XCTUnwrap(repositories.first)

    let snapshot = try await workspace.snapshot(of: repository)

    let main = try XCTUnwrap(snapshot.worktrees.first { $0.isMain })
    let knownStale = try XCTUnwrap(snapshot.worktrees.first { $0.branch == "agent-task" })
    let unavailable = try XCTUnwrap(
      snapshot.worktrees.first { $0.head == String(repeating: "f", count: 40) })
    XCTAssertNotNil(main.commitDate)
    XCTAssertEqual(knownStale.commitDate, main.commitDate)
    XCTAssertTrue(knownStale.isPrunable)
    XCTAssertNil(unavailable.commitDate)
  }

  func testSnapshotListsMainAndLinkedWorktrees() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.base)
    )
    let repository = try XCTUnwrap(repositories.first)

    let snapshot = try await workspace.snapshot(of: repository)

    XCTAssertEqual(snapshot.repository, repository)
    XCTAssertEqual(
      snapshot.worktrees.map(\.path),
      [
        fixture.repository.resolvingSymlinksInPath(),
        fixture.linkedWorktree.resolvingSymlinksInPath(),
      ]
    )
    XCTAssertEqual(snapshot.worktrees.map(\.branch), ["main", "agent-task"])
    XCTAssertEqual(snapshot.worktrees.map(\.isMain), [true, false])
    XCTAssertEqual(snapshot.worktrees.map(\.canCleanUpRegistration), [false, false])
  }

  func testSnapshotReportsUntrackedFilesInLinkedWorktree() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try Data("uncommitted work".utf8).write(
      to: fixture.linkedWorktree.appending(path: "notes.txt")
    )
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.base)
    )
    let repository = try XCTUnwrap(repositories.first)

    let snapshot = try await workspace.snapshot(of: repository)

    let linkedWorktree = try XCTUnwrap(
      snapshot.worktrees.first { !$0.isMain }
    )
    let status = try XCTUnwrap(linkedWorktree.status)
    XCTAssertFalse(status.isClean)
    XCTAssertEqual(status.untrackedFileCount, 1)
    XCTAssertEqual(status.stagedFileCount, 0)
    XCTAssertEqual(status.modifiedFileCount, 0)
    XCTAssertEqual(status.conflictedFileCount, 0)
  }

  func testSnapshotReportsLockedWorktreeAndReason() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try runGit(
      ["worktree", "lock", "--reason", "Agent is running", fixture.linkedWorktree.path],
      in: fixture.repository
    )
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.base)
    )
    let repository = try XCTUnwrap(repositories.first)

    let snapshot = try await workspace.snapshot(of: repository)

    let linkedWorktree = try XCTUnwrap(
      snapshot.worktrees.first { !$0.isMain }
    )
    XCTAssertTrue(linkedWorktree.isLocked)
    XCTAssertEqual(linkedWorktree.lockReason, "Agent is running")
  }

  func testSnapshotRecommendsCleanLinkedWorktreeWhoseHeadIsInRemoteDefaultBranch() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try configureRemoteDefaultBranch(in: fixture.repository)
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.base)
    )
    let repository = try XCTUnwrap(repositories.first)

    let snapshot = try await workspace.snapshot(of: repository)

    let linkedWorktree = try XCTUnwrap(
      snapshot.worktrees.first { !$0.isMain }
    )
    XCTAssertEqual(
      linkedWorktree.cleanupRecommendation,
      .cleanable(target: "origin/main")
    )
  }

  func testDiskUsageStreamsWorktreeAndSharedGitMeasurements() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try Data(repeating: 0xA5, count: 4_096).write(
      to: fixture.linkedWorktree.appending(path: "generated.bin")
    )
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.base)
    )
    let repository = try XCTUnwrap(repositories.first)

    let snapshot = try await workspace.snapshot(of: repository)
    var worktreeUsage: [URL: Int64] = [:]
    var sharedGitUsage: Int64?

    for try await update in workspace.diskUsage(of: snapshot) {
      switch update {
      case .worktree(let path, let allocatedBytes):
        worktreeUsage[path] = allocatedBytes
      case .sharedGit(let allocatedBytes):
        sharedGitUsage = allocatedBytes
      }
    }

    XCTAssertGreaterThanOrEqual(
      try XCTUnwrap(worktreeUsage[fixture.linkedWorktree.resolvingSymlinksInPath()]),
      4_096
    )
    XCTAssertGreaterThan(try XCTUnwrap(sharedGitUsage), 0)
  }

  func testDiskUsageSkipsWorktreesWithRetainedMeasurements() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.base)
    )
    let repository = try XCTUnwrap(repositories.first)
    let snapshot = try await workspace.snapshot(of: repository)
    let linkedWorktree = try XCTUnwrap(snapshot.worktrees.first { !$0.isMain })
    try FileManager.default.removeItem(at: fixture.linkedWorktree)
    var measuredPaths: [URL] = []
    var sharedGitBytes: Int64?

    for try await update in workspace.diskUsage(
      of: snapshot,
      excludingWorktreePaths: [linkedWorktree.path]
    ) {
      switch update {
      case .worktree(let path, _):
        measuredPaths.append(path)
      case .sharedGit(let bytes):
        sharedGitBytes = bytes
      }
    }

    XCTAssertEqual(measuredPaths, [snapshot.worktrees[0].path])
    XCTAssertGreaterThan(try XCTUnwrap(sharedGitBytes), 0)
  }

  func testSnapshotKeepsMissingWorktreeAsPrunableRecord() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try FileManager.default.removeItem(at: fixture.linkedWorktree)
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.base)
    )
    let repository = try XCTUnwrap(repositories.first)

    let snapshot = try await workspace.snapshot(of: repository)

    let missingWorktree = try XCTUnwrap(
      snapshot.worktrees.first { !$0.isMain }
    )
    XCTAssertTrue(missingWorktree.isPrunable)
    XCTAssertTrue(missingWorktree.canCleanUpRegistration)
    XCTAssertNotNil(missingWorktree.prunableReason)
    XCTAssertNil(missingWorktree.status)
  }

  func testSnapshotKeepsLockedMissingRegistrationIneligibleForCleanup() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try runGit(["worktree", "lock", fixture.linkedWorktree.path], in: fixture.repository)
    try FileManager.default.removeItem(at: fixture.linkedWorktree)
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.base)
    )
    let repository = try XCTUnwrap(repositories.first)

    let snapshot = try await workspace.snapshot(of: repository)

    let missingWorktree = try XCTUnwrap(snapshot.worktrees.first { !$0.isMain })
    XCTAssertTrue(missingWorktree.isPrunable)
    XCTAssertTrue(missingWorktree.isLocked)
    XCTAssertFalse(missingWorktree.canCleanUpRegistration)
  }

  func testSnapshotKeepsLockedRegistrationWithMissingGitFileIneligibleForCleanup() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try runGit(["worktree", "lock", fixture.linkedWorktree.path], in: fixture.repository)
    try FileManager.default.removeItem(at: fixture.linkedWorktree.appending(path: ".git"))
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.repository))
    let repository = try XCTUnwrap(repositories.first)

    let snapshot = try await workspace.snapshot(of: repository)

    let worktree = try XCTUnwrap(snapshot.worktrees.first { !$0.isMain })
    XCTAssertTrue(worktree.isPrunable)
    XCTAssertTrue(worktree.isLocked)
    XCTAssertFalse(worktree.canCleanUpRegistration)
    XCTAssertNil(worktree.status)
  }
}
