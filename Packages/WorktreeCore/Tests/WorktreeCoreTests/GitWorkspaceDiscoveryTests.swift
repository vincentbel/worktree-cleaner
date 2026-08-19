import Foundation
import WorktreeCore
import XCTest

final class GitWorkspaceDiscoveryTests: XCTestCase {
  func testDiscoverReturnsRepositoryBelowSelectedDirectory() async throws {
    let baseDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: baseDirectory) }

    let repositoryDirectory = baseDirectory.appending(path: "sample-project")
    try FileManager.default.createDirectory(
      at: repositoryDirectory,
      withIntermediateDirectories: true
    )
    try runGit(["init", "--quiet"], in: repositoryDirectory)

    let repositories = try await collectRepositories(
      from: GitWorkspace().discover(in: baseDirectory)
    )

    XCTAssertEqual(repositories.count, 1)
    XCTAssertEqual(repositories.first?.name, "sample-project")
    XCTAssertEqual(
      repositories.first?.workingTreeURL,
      repositoryDirectory.resolvingSymlinksInPath()
    )
  }

  func testDiscoverGroupsLinkedWorktreeUnderMainRepository() async throws {
    let baseDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: baseDirectory) }

    let repositoryDirectory = baseDirectory.appending(path: "project")
    let linkedWorktreeDirectory = baseDirectory.appending(path: "project-agent")
    try FileManager.default.createDirectory(
      at: repositoryDirectory,
      withIntermediateDirectories: true
    )
    try runGit(["init", "--quiet"], in: repositoryDirectory)
    try runGit(
      [
        "-c", "user.name=Worktree Manager Tests",
        "-c", "user.email=tests@example.com",
        "commit", "--quiet", "--allow-empty", "-m", "Initial commit",
      ],
      in: repositoryDirectory
    )
    try runGit(
      ["worktree", "add", "--quiet", "-b", "agent-task", linkedWorktreeDirectory.path],
      in: repositoryDirectory
    )

    let repositories = try await collectRepositories(
      from: GitWorkspace().discover(in: baseDirectory)
    )

    XCTAssertEqual(repositories.count, 1)
    XCTAssertEqual(
      repositories.first?.workingTreeURL,
      repositoryDirectory.resolvingSymlinksInPath()
    )
  }

  func testDiscoverContinuesIntoProjectSubdirectoriesButSkipsGeneratedDirectories()
    async throws
  {
    let baseDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: baseDirectory) }

    try runGit(["init", "--quiet"], in: baseDirectory)

    let nestedRepository = baseDirectory.appending(path: "Sources/NestedProject")
    try FileManager.default.createDirectory(
      at: nestedRepository,
      withIntermediateDirectories: true
    )
    try runGit(["init", "--quiet"], in: nestedRepository)

    let generatedRepository = baseDirectory.appending(path: "node_modules/dependency")
    try FileManager.default.createDirectory(
      at: generatedRepository,
      withIntermediateDirectories: true
    )
    try runGit(["init", "--quiet"], in: generatedRepository)

    let repositories = try await collectRepositories(
      from: GitWorkspace().discover(in: baseDirectory)
    )

    XCTAssertEqual(
      Set(repositories.map(\.workingTreeURL)),
      Set([
        baseDirectory.resolvingSymlinksInPath(),
        nestedRepository.resolvingSymlinksInPath(),
      ])
    )
  }
}
