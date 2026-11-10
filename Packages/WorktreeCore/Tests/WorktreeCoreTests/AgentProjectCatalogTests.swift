import Foundation
import SQLite3
import XCTest

@testable import WorktreeCore

final class AgentProjectCatalogTests: XCTestCase {
  func testReadsCodexProjectRootsWithoutChangingTheDatabase() async throws {
    let base = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let database = base.appending(path: "state_5.sqlite")
    let first = base.appending(path: "first")
    let second = base.appending(path: "second")
    let connection = try makeDatabase(at: database)
    try insertProject(connection, id: "project", name: "Two folders", paths: [first, second])
    sqlite3_close(connection)
    let original = try Data(contentsOf: database)
    let catalog = makeCatalog(base)

    let snapshot = await catalog.snapshot()

    XCTAssertTrue(snapshot.canAutomaticallySelect)
    XCTAssertEqual(
      Set(snapshot.projects.map(\.path)), Set([first, second].map(WorkspaceRoots.normalize)))
    XCTAssertEqual(snapshot.projects.map(\.name), ["Two folders", "Two folders"])
    XCTAssertEqual(snapshot.projects.map(\.application), [.codex, .codex])
    XCTAssertEqual(try Data(contentsOf: database), original)
  }

  func testUsesTheNewestStateDatabase() async throws {
    let base = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    for version in [5, 6] {
      let connection = try makeDatabase(at: base.appending(path: "state_\(version).sqlite"))
      try insertProject(
        connection, id: "project", name: "Version \(version)",
        paths: [base.appending(path: "version-\(version)")])
      sqlite3_close(connection)
    }

    let snapshot = await makeCatalog(base).snapshot()

    XCTAssertEqual(snapshot.projects.map(\.name), ["Version 6"])
  }

  func testReadsExplicitClaudeCodeFolderBindingsAcrossAccounts() async throws {
    let base = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let code = base.appending(path: "code")
    let otherCode = base.appending(path: "other-code")
    let documents = base.appending(path: "documents")
    try writeSpaces(
      base, account: "first",
      spaces: [
        [
          "id": "code", "name": "Code project", "ccdFolderPath": code.path,
          "folders": [["path": documents.path]],
        ],
        ["id": "documents", "name": "Documents", "folders": [["path": documents.path]]],
      ])
    try writeSpaces(
      base, account: "second",
      spaces: [["id": "other-code", "name": "Other code", "ccdFolderPath": otherCode.path]])

    let snapshot = await makeCatalog(base).snapshot()

    XCTAssertTrue(snapshot.canAutomaticallySelect)
    XCTAssertEqual(
      Set(snapshot.projects.map(\.path)), Set([code, otherCode].map(WorkspaceRoots.normalize)))
    XCTAssertEqual(snapshot.projects.map(\.application), [.claudeCode, .claudeCode])
  }

  func testMatchesWorktreeRootsAndSubfoldersThroughSymlinks() async throws {
    let base = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let worktree = base.appending(path: "worktree")
    let subfolder = worktree.appending(path: "Sources")
    try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
    let alias = base.appending(path: "alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: worktree)
    let connection = try makeDatabase(at: base.appending(path: "state_5.sqlite"))
    try insertProject(
      connection, id: "project", name: "Source folder", paths: [alias.appending(path: "Sources")])
    sqlite3_close(connection)
    let snapshot = await makeCatalog(base).snapshot()
    let sibling = base.appending(path: "worktree-other")
    let nestedWorktree = subfolder.appending(path: "nested")

    let associations = snapshot.associations(for: [worktree, alias, sibling, nestedWorktree])

    XCTAssertEqual(associations[worktree]?.map(\.name), ["Source folder"])
    XCTAssertEqual(associations[alias]?.map(\.name), ["Source folder"])
    XCTAssertNil(associations[sibling])
    XCTAssertNil(associations[nestedWorktree])
  }

  func testRefreshSeesProjectsCommittedToTheWriteAheadLog() async throws {
    let base = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let database = base.appending(path: "state_5.sqlite")
    let connection = try makeDatabase(at: database)
    defer { sqlite3_close(connection) }
    try execute(connection, "PRAGMA journal_mode = WAL; PRAGMA wal_autocheckpoint = 0;")
    try insertProject(
      connection, id: "first", name: "First", paths: [base.appending(path: "first")])
    let catalog = makeCatalog(base)
    let initial = await catalog.snapshot()
    XCTAssertEqual(initial.projects.count, 1)
    let originalDatabase = try Data(contentsOf: database)
    try insertProject(
      connection, id: "second", name: "Second", paths: [base.appending(path: "second")])
    XCTAssertEqual(try Data(contentsOf: database), originalDatabase)

    let refreshed = await catalog.snapshot()

    XCTAssertEqual(Set(refreshed.projects.map(\.name)), ["First", "Second"])
  }

  func testMatchesTheCanonicalPathsFromARepositorySnapshot() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let database = try makeDatabase(at: fixture.base.appending(path: "state_5.sqlite"))
    try insertProject(
      database, id: "project", name: "Agent work",
      paths: [fixture.linkedWorktree.appending(path: "Sources")])
    sqlite3_close(database)
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.repository))
    let repository = try XCTUnwrap(repositories.first)
    let gitSnapshot = try await workspace.snapshot(of: repository)
    let projects = await makeCatalog(fixture.base).snapshot()
    let worktree = try XCTUnwrap(gitSnapshot.worktrees.first { !$0.isMain })

    let associations = projects.associations(for: gitSnapshot)

    XCTAssertEqual(associations[worktree.path]?.map(\.name), ["Agent work"])
    XCTAssertEqual(associations.count, 1)
  }

  func testInitialReadFailureSkipsAutomaticSelectionAndCanRecover() async throws {
    let base = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let database = base.appending(path: "state_5.sqlite")
    try Data("unreadable database".utf8).write(to: database)
    let catalog = makeCatalog(base)

    let failed = await catalog.snapshot()

    XCTAssertFalse(failed.canAutomaticallySelect)
    try FileManager.default.removeItem(at: database)
    let connection = try makeDatabase(at: database)
    sqlite3_close(connection)

    let recovered = await catalog.snapshot()

    XCTAssertTrue(recovered.canAutomaticallySelect)
    XCTAssertTrue(recovered.projects.isEmpty)
  }

  func testReadFailureKeepsTheLastSuccessfulProjects() async throws {
    let base = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let database = base.appending(path: "state_5.sqlite")
    let connection = try makeDatabase(at: database)
    try insertProject(
      connection, id: "project", name: "Keep", paths: [base.appending(path: "keep")])
    sqlite3_close(connection)
    let catalog = makeCatalog(base)
    let initial = await catalog.snapshot()
    try FileManager.default.removeItem(at: database)
    try Data("unreadable database".utf8).write(to: database)

    let failed = await catalog.snapshot()

    XCTAssertEqual(failed, initial)
  }

  func testMissingApplicationsHaveNoProjectAssociations() async throws {
    let base = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }

    let snapshot = await makeCatalog(base).snapshot()

    XCTAssertTrue(snapshot.canAutomaticallySelect)
    XCTAssertTrue(snapshot.projects.isEmpty)
  }

  func testMalformedClaudeBindingsSkipAutomaticSelectionAndCanRecover() async throws {
    let base = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let file = try writeSpaces(base, account: "first", spaces: [])
    try Data("{".utf8).write(to: file)
    let catalog = makeCatalog(base)
    let failed = await catalog.snapshot()
    XCTAssertFalse(failed.canAutomaticallySelect)
    try writeSpaces(
      base, account: "first",
      spaces: [["id": "project", "name": "Recovered", "ccdFolderPath": base.path]])

    let recovered = await catalog.snapshot()

    XCTAssertTrue(recovered.canAutomaticallySelect)
    XCTAssertEqual(recovered.projects.map(\.name), ["Recovered"])
  }

  private func makeCatalog(_ base: URL) -> AgentProjectCatalog {
    AgentProjectCatalog(
      codexDirectory: base,
      claudeSessionsDirectory: base.appending(path: "claude"))
  }

  @discardableResult
  private func writeSpaces(
    _ base: URL, account: String, spaces: [[String: Any]]
  ) throws -> URL {
    let directory = base.appending(path: "claude/organization/\(account)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appending(path: "spaces.json")
    try JSONSerialization.data(withJSONObject: ["spaces": spaces]).write(to: file)
    return file
  }

  private func makeDatabase(at path: URL) throws -> OpaquePointer {
    var connection: OpaquePointer?
    XCTAssertEqual(sqlite3_open(path.path, &connection), SQLITE_OK)
    let database = try XCTUnwrap(connection)
    try execute(
      database,
      """
      CREATE TABLE projects (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE project_roots (
        project_id TEXT NOT NULL, path TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0
      );
      """)
    return database
  }

  private func insertProject(
    _ database: OpaquePointer, id: String, name: String, paths: [URL]
  ) throws {
    try insert(database, "INSERT INTO projects (id, name) VALUES (?, ?)", values: [id, name])
    for path in paths {
      try insert(
        database, "INSERT INTO project_roots (project_id, path) VALUES (?, ?)",
        values: [id, path.path])
    }
  }

  private func insert(_ database: OpaquePointer, _ sql: String, values: [String]) throws {
    var statement: OpaquePointer?
    XCTAssertEqual(sqlite3_prepare_v2(database, sql, -1, &statement, nil), SQLITE_OK)
    let prepared = try XCTUnwrap(statement)
    defer { sqlite3_finalize(prepared) }
    for (index, value) in values.enumerated() {
      let result = value.withCString {
        sqlite3_bind_text(
          prepared, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
      }
      XCTAssertEqual(result, SQLITE_OK)
    }
    XCTAssertEqual(sqlite3_step(prepared), SQLITE_DONE)
  }

  private func execute(_ database: OpaquePointer, _ sql: String) throws {
    let result = sqlite3_exec(database, sql, nil, nil, nil)
    guard result == SQLITE_OK else {
      throw NSError(
        domain: "AgentProjectCatalogTests", code: Int(result),
        userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
  }
}
