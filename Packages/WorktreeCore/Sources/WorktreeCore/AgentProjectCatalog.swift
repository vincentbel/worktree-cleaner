import Foundation
import OSLog
import SQLite3

public enum AgentApplication: String, CaseIterable, Sendable {
  case codex
  case claudeCode
}

public struct AgentProject: Equatable, Sendable {
  public let application: AgentApplication
  public let id: String
  public let name: String
  public let path: URL
}

public struct AgentProjectSnapshot: Equatable, Sendable {
  public let projects: [AgentProject]
  public let canAutomaticallySelect: Bool

  public init(projects: [AgentProject], canAutomaticallySelect: Bool) {
    self.projects = projects
    self.canAutomaticallySelect = canAutomaticallySelect
  }

  public func associations(for worktreePaths: [URL]) -> [URL: [AgentProject]] {
    matchingProjects(Dictionary(grouping: worktreePaths, by: WorkspaceRoots.normalize))
  }

  public func associations(for snapshot: RepositorySnapshot) -> [URL: [AgentProject]] {
    matchingProjects(Dictionary(grouping: snapshot.worktrees.map(\.path), by: { $0 }))
  }

  private func matchingProjects(_ pathsByRoot: [URL: [URL]]) -> [URL: [AgentProject]] {
    var result: [URL: [AgentProject]] = [:]
    for project in projects {
      var parent = project.path
      while true {
        for path in pathsByRoot[parent] ?? [] {
          result[path, default: []].append(project)
        }
        let next = parent.deletingLastPathComponent()
        guard next != parent else { break }
        parent = next
      }
    }
    return result
  }
}

public actor AgentProjectCatalog {
  private struct FileStamp: Equatable {
    let path: URL
    let size: UInt64
    let inode: UInt64
    let modifiedAt: Date?
  }

  private struct Cache {
    let stamps: [FileStamp]
    let projects: [AgentProject]
  }

  private struct ClaudeSpaces: Decodable {
    struct Space: Decodable {
      let id: String
      let name: String
      let ccdFolderPath: String?
    }
    let spaces: [Space]
  }

  private enum ReadError: Error {
    case sqlite(String)
    case invalidProjectPath(String)
  }

  private let codexDirectory: URL
  private let claudeSessionsDirectory: URL
  private var caches: [AgentApplication: Cache] = [:]
  private let logger = Logger(subsystem: "dev.worktreecleaner.app", category: "AgentProjects")

  public init(codexDirectory: URL? = nil, claudeSessionsDirectory: URL? = nil) {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let configuredCodexDirectory = ProcessInfo.processInfo.environment["CODEX_HOME"]
      .flatMap { $0.isEmpty ? nil : URL(filePath: $0) }
    self.codexDirectory =
      codexDirectory ?? configuredCodexDirectory ?? home.appending(path: ".codex")
    self.claudeSessionsDirectory =
      claudeSessionsDirectory
      ?? home.appending(path: "Library/Application Support/Claude/local-agent-mode-sessions")
  }

  public func snapshot() -> AgentProjectSnapshot {
    for application in AgentApplication.allCases {
      do {
        let files = try projectFiles(for: application)
        var watchedFiles = files
        if application == .codex, let database = files.first {
          watchedFiles.append(URL(filePath: database.path + "-wal"))
        }
        let stamps = try watchedFiles.compactMap(fileStamp)
        if caches[application]?.stamps == stamps { continue }
        let projects: [AgentProject]
        switch application {
        case .codex:
          projects = try files.first.map(readCodexProjects) ?? []
        case .claudeCode:
          projects = try files.flatMap(readClaudeProjects)
        }
        caches[application] = Cache(stamps: stamps, projects: projects)
      } catch {
        logger.error(
          "Could not refresh \(application.rawValue, privacy: .public) projects: \(String(describing: error), privacy: .private)"
        )
      }
    }
    return AgentProjectSnapshot(
      projects: AgentApplication.allCases.flatMap { caches[$0]?.projects ?? [] },
      canAutomaticallySelect: AgentApplication.allCases.allSatisfy { caches[$0] != nil }
    )
  }

  private func projectFiles(for application: AgentApplication) throws -> [URL] {
    switch application {
    case .codex:
      let databases = try contents(of: codexDirectory).compactMap { path -> (Int, URL)? in
        let name = path.lastPathComponent
        guard name.hasPrefix("state_"), name.hasSuffix(".sqlite"),
          let version = Int(name.dropFirst(6).dropLast(7))
        else { return nil }
        return (version, path)
      }
      return databases.max(by: { $0.0 < $1.0 }).map { [$0.1] } ?? []
    case .claudeCode:
      var files: [URL] = []
      for organization in try directories(in: claudeSessionsDirectory) {
        for account in try directories(in: organization) {
          let file = account.appending(path: "spaces.json")
          if try fileStamp(file) != nil { files.append(file) }
        }
      }
      return files.sorted { $0.path < $1.path }
    }
  }

  private func contents(of directory: URL) throws -> [URL] {
    do {
      return try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles])
    } catch {
      if isMissingFile(error) { return [] }
      throw error
    }
  }

  private func directories(in directory: URL) throws -> [URL] {
    try contents(of: directory).filter {
      let values = try $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      return values.isDirectory == true && values.isSymbolicLink != true
    }
  }

  private func fileStamp(_ file: URL) throws -> FileStamp? {
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
      return FileStamp(
        path: file,
        size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
        inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
        modifiedAt: attributes[.modificationDate] as? Date)
    } catch {
      if isMissingFile(error) { return nil }
      throw error
    }
  }

  private func isMissingFile(_ error: Error) -> Bool {
    let error = error as NSError
    return error.domain == NSCocoaErrorDomain
      && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError)
  }

  private func readCodexProjects(_ file: URL) throws -> [AgentProject] {
    var database: OpaquePointer?
    let opened = sqlite3_open_v2(
      file.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
    defer { sqlite3_close(database) }
    guard opened == SQLITE_OK else {
      throw ReadError.sqlite(String(cString: sqlite3_errmsg(database)))
    }
    sqlite3_busy_timeout(database, 100)
    var statement: OpaquePointer?
    let query = """
      SELECT p.id, p.name, r.path
      FROM projects AS p JOIN project_roots AS r ON r.project_id = p.id
      ORDER BY p.position, r.position
      """
    guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
      throw ReadError.sqlite(String(cString: sqlite3_errmsg(database)))
    }
    defer { sqlite3_finalize(statement) }
    var projects: [AgentProject] = []
    while true {
      switch sqlite3_step(statement) {
      case SQLITE_ROW:
        guard let id = sqlite3_column_text(statement, 0),
          let name = sqlite3_column_text(statement, 1),
          let path = sqlite3_column_text(statement, 2)
        else { throw ReadError.sqlite("Missing project fields") }
        projects.append(
          AgentProject(
            application: .codex, id: String(cString: id), name: String(cString: name),
            path: try projectPath(String(cString: path))))
      case SQLITE_DONE:
        return projects
      default:
        throw ReadError.sqlite(String(cString: sqlite3_errmsg(database)))
      }
    }
  }

  private func readClaudeProjects(_ file: URL) throws -> [AgentProject] {
    let data = try JSONDecoder().decode(ClaudeSpaces.self, from: Data(contentsOf: file))
    return try data.spaces.compactMap { space in
      guard let path = space.ccdFolderPath else { return nil }
      return AgentProject(
        application: .claudeCode, id: "\(file.path):\(space.id)", name: space.name,
        path: try projectPath(path))
    }
  }

  private func projectPath(_ path: String) throws -> URL {
    guard path.hasPrefix("/") else { throw ReadError.invalidProjectPath(path) }
    return WorkspaceRoots.normalize(URL(filePath: path, directoryHint: .isDirectory))
  }
}
