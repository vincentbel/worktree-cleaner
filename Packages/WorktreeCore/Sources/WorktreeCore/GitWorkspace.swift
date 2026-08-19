import Foundation

public struct GitWorkspace: Sendable {
  public init() {}

  public func discover(
    in baseDirectory: URL
  ) -> AsyncThrowingStream<GitRepository, Error> {
    AsyncThrowingStream { continuation in
      let task = Task.detached {
        do {
          try discoverRepositories(in: baseDirectory) { repository in
            continuation.yield(repository)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  public func snapshot(of repository: GitRepository) async throws -> RepositorySnapshot {
    let runner = GitCommandRunner()
    let output = try runner.runData(
      ["worktree", "list", "--porcelain", "-z", "--expire", "now"],
      in: repository.workingTreeURL
    )
    let cleanupTarget = try cleanupTarget(in: repository, using: runner)
    let worktrees = try parseWorktrees(
      output,
      repository: repository,
      cleanupTarget: cleanupTarget
    )
    let refreshedRepository = GitRepository(
      workingTreeURL: repository.workingTreeURL,
      commonGitDirectoryURL: repository.commonGitDirectoryURL,
      linkedWorktreeCount: max(0, worktrees.count - 1)
    )
    return RepositorySnapshot(
      repository: refreshedRepository,
      worktrees: worktrees
    )
  }

  public func diskUsage(
    of snapshot: RepositorySnapshot
  ) -> AsyncThrowingStream<DiskUsageUpdate, Error> {
    AsyncThrowingStream { continuation in
      let task = Task.detached {
        do {
          let measurer = DiskUsageMeasurer()
          for worktree in snapshot.worktrees where !worktree.isPrunable {
            try Task.checkCancellation()
            let allocatedBytes = try measurer.allocatedSize(
              of: worktree.path,
              excludingImmediateGitEntry: true
            )
            continuation.yield(
              .worktree(path: worktree.path, allocatedBytes: allocatedBytes)
            )
          }
          let sharedGitAllocatedBytes = try measurer.allocatedSize(
            of: snapshot.repository.commonGitDirectoryURL
          )
          continuation.yield(.sharedGit(allocatedBytes: sharedGitAllocatedBytes))
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  public func remove(
    _ worktree: GitWorktree,
    from repository: GitRepository
  ) async throws -> RepositorySnapshot {
    let currentSnapshot = try await snapshot(of: repository)
    guard let currentWorktree = currentSnapshot.worktrees.first(where: { $0.id == worktree.id })
    else {
      throw GitWorkspaceError.worktreeNotRegistered(worktree.path)
    }
    switch currentWorktree.cleanupRecommendation {
    case .cleanable, .needsReview(reason: .notMerged):
      break
    default:
      throw GitWorkspaceError.worktreeNotCleanable(
        currentWorktree.path,
        currentWorktree.cleanupRecommendation
      )
    }

    _ = try GitCommandRunner().runData(
      ["worktree", "remove", currentWorktree.path.path],
      in: repository.workingTreeURL
    )
    return try await snapshot(of: repository)
  }

  private func discoverRepositories(
    in baseDirectory: URL,
    yield: (GitRepository) -> Void
  ) throws {
    let values = try baseDirectory.resourceValues(forKeys: [.isDirectoryKey])
    guard values.isDirectory == true else {
      throw GitWorkspaceError.notDirectory(baseDirectory)
    }

    var scanError: Error?
    guard
      let enumerator = FileManager.default.enumerator(
        at: baseDirectory,
        includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
        errorHandler: { _, error in
          scanError = error
          return false
        }
      )
    else {
      throw GitWorkspaceError.cannotEnumerate(baseDirectory)
    }

    var discoveredCommonDirectories: Set<URL> = []
    while let entry = enumerator.nextObject() as? URL {
      try Task.checkCancellation()
      let resourceValues = try entry.resourceValues(
        forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
      )

      if resourceValues.isSymbolicLink == true {
        enumerator.skipDescendants()
        continue
      }

      if resourceValues.isDirectory == true,
        Self.skippedDirectoryNames.contains(entry.lastPathComponent)
      {
        enumerator.skipDescendants()
        continue
      }

      guard entry.lastPathComponent == ".git" else { continue }
      let repository = try repository(at: entry.deletingLastPathComponent())
      if discoveredCommonDirectories.insert(repository.commonGitDirectoryURL).inserted {
        yield(repository)
      }

      if resourceValues.isDirectory == true {
        enumerator.skipDescendants()
      }
    }

    if let scanError {
      throw scanError
    }
  }

  private static let skippedDirectoryNames: Set<String> = [
    ".build",
    ".cache",
    ".gradle",
    ".m2",
    ".next",
    ".nuxt",
    ".pnpm-store",
    ".pytest_cache",
    ".repo",
    ".swiftpm",
    ".terraform",
    ".tox",
    ".venv",
    ".yarn",
    "Carthage",
    "DerivedData",
    "Pods",
    "__pycache__",
    "build",
    "dist",
    "node_modules",
    "target",
    "venv",
    "vendor",
  ]

  private func repository(at candidate: URL) throws -> GitRepository {
    let runner = GitCommandRunner()
    let worktreeList = try runner.runData(
      ["worktree", "list", "--porcelain", "-z", "--expire", "now"],
      in: candidate
    )
    let fields = String(decoding: worktreeList, as: UTF8.self)
      .split(separator: "\0", omittingEmptySubsequences: true)
    guard let firstField = fields.first,
      firstField.hasPrefix("worktree ")
    else {
      throw GitWorkspaceError.invalidWorktreeList(candidate)
    }

    let workingTree = firstField.dropFirst("worktree ".count)
    let commonGitDirectory = try runner.run(
      ["rev-parse", "--path-format=absolute", "--git-common-dir"],
      in: candidate
    )
    let worktreeCount = fields.count { $0.hasPrefix("worktree ") }

    return GitRepository(
      workingTreeURL: canonicalURL(URL(filePath: String(workingTree))),
      commonGitDirectoryURL: canonicalURL(URL(filePath: commonGitDirectory)),
      linkedWorktreeCount: max(0, worktreeCount - 1)
    )
  }

  private func parseWorktrees(
    _ data: Data,
    repository: GitRepository,
    cleanupTarget: String?
  ) throws -> [GitWorktree] {
    let fields = String(decoding: data, as: UTF8.self)
      .components(separatedBy: "\0")
    var worktrees: [GitWorktree] = []
    var path: String?
    var head: String?
    var branch: String?
    var isDetached = false
    var isLocked = false
    var lockReason: String?
    var isPrunable = false
    var prunableReason: String?

    for field in fields {
      if field.isEmpty {
        if let path, let head {
          let worktreeURL = canonicalURL(URL(filePath: path))
          let pathExists = FileManager.default.fileExists(atPath: worktreeURL.path)
          isPrunable = isPrunable || !pathExists
          let status: WorktreeStatus?
          if isPrunable {
            status = nil
          } else {
            let statusOutput = try GitCommandRunner().runData(
              ["status", "--porcelain=v2", "--branch", "-z"],
              in: worktreeURL
            )
            status = parseStatus(statusOutput)
          }
          let isMain = worktrees.isEmpty
          worktrees.append(
            GitWorktree(
              path: worktreeURL,
              head: head,
              branch: branch,
              isDetached: isDetached,
              isMain: isMain,
              isLocked: isLocked,
              lockReason: lockReason,
              isPrunable: isPrunable,
              prunableReason: prunableReason,
              status: status,
              cleanupRecommendation: try cleanupRecommendation(
                head: head,
                isMain: isMain,
                isLocked: isLocked,
                lockReason: lockReason,
                isPrunable: isPrunable,
                prunableReason: prunableReason,
                status: status,
                target: cleanupTarget,
                repository: repository
              )
            )
          )
        }
        path = nil
        head = nil
        branch = nil
        isDetached = false
        isLocked = false
        lockReason = nil
        isPrunable = false
        prunableReason = nil
      } else if field.hasPrefix("worktree ") {
        path = String(field.dropFirst("worktree ".count))
      } else if field.hasPrefix("HEAD ") {
        head = String(field.dropFirst("HEAD ".count))
      } else if field.hasPrefix("branch refs/heads/") {
        branch = String(field.dropFirst("branch refs/heads/".count))
      } else if field == "detached" {
        isDetached = true
      } else if field == "locked" {
        isLocked = true
      } else if field.hasPrefix("locked ") {
        isLocked = true
        lockReason = String(field.dropFirst("locked ".count))
      } else if field == "prunable" {
        isPrunable = true
      } else if field.hasPrefix("prunable ") {
        isPrunable = true
        prunableReason = String(field.dropFirst("prunable ".count))
      }
    }

    guard !worktrees.isEmpty else {
      throw GitWorkspaceError.invalidWorktreeList(repository.workingTreeURL)
    }
    return worktrees
  }

  private func cleanupTarget(
    in repository: GitRepository,
    using runner: GitCommandRunner
  ) throws -> String? {
    do {
      return try runner.run(
        ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"],
        in: repository.workingTreeURL
      )
    } catch let error as GitCommandError where error.terminationStatus == 1 {
      return nil
    }
  }

  private func cleanupRecommendation(
    head: String,
    isMain: Bool,
    isLocked: Bool,
    lockReason: String?,
    isPrunable: Bool,
    prunableReason: String?,
    status: WorktreeStatus?,
    target: String?,
    repository: GitRepository
  ) throws -> CleanupRecommendation {
    if isMain {
      return .protectedMainWorktree
    }

    var blockers: [CleanupBlocker] = []
    if isPrunable {
      blockers.append(.missing(reason: prunableReason))
    }
    if isLocked {
      blockers.append(.locked(reason: lockReason))
    }
    if let status, !status.isClean {
      blockers.append(.uncommittedChanges)
    }
    if !blockers.isEmpty {
      return .blocked(reasons: blockers)
    }

    guard let target else {
      return .needsReview(reason: .cleanupTargetUnavailable)
    }

    do {
      _ = try GitCommandRunner().runData(
        ["merge-base", "--is-ancestor", head, target],
        in: repository.workingTreeURL
      )
      return .cleanable(target: target)
    } catch let error as GitCommandError where error.terminationStatus == 1 {
      return .needsReview(reason: .notMerged(target: target))
    }
  }

  private func parseStatus(_ data: Data) -> WorktreeStatus {
    var stagedFileCount = 0
    var modifiedFileCount = 0
    var untrackedFileCount = 0
    var conflictedFileCount = 0

    for field in String(decoding: data, as: UTF8.self)
      .components(separatedBy: "\0")
    {
      if field.hasPrefix("? ") {
        untrackedFileCount += 1
      } else if field.hasPrefix("u ") {
        conflictedFileCount += 1
      } else if field.hasPrefix("1 ") || field.hasPrefix("2 ") {
        let parts = field.split(separator: " ", maxSplits: 2)
        guard parts.count > 1 else { continue }
        let state = Array(parts[1].utf8)
        guard state.count == 2 else { continue }
        if state[0] != Character(".").asciiValue {
          stagedFileCount += 1
        }
        if state[1] != Character(".").asciiValue {
          modifiedFileCount += 1
        }
      }
    }

    return WorktreeStatus(
      stagedFileCount: stagedFileCount,
      modifiedFileCount: modifiedFileCount,
      untrackedFileCount: untrackedFileCount,
      conflictedFileCount: conflictedFileCount
    )
  }
}

public enum GitWorkspaceError: Error, Equatable {
  case notDirectory(URL)
  case cannotEnumerate(URL)
  case invalidWorktreeList(URL)
  case cannotMeasureDiskUsage(URL)
  case worktreeNotRegistered(URL)
  case worktreeNotCleanable(URL, CleanupRecommendation)
}

extension GitWorkspaceError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .notDirectory(let url):
      "The selected path is not a directory: \(url.path)"
    case .cannotEnumerate(let url):
      "The selected directory cannot be scanned: \(url.path)"
    case .invalidWorktreeList(let url):
      "Git returned an invalid worktree list for: \(url.path)"
    case .cannotMeasureDiskUsage(let url):
      "Disk usage cannot be measured for: \(url.path)"
    case .worktreeNotRegistered(let url):
      "The worktree is no longer registered: \(url.path)"
    case .worktreeNotCleanable(let url, _):
      "The worktree no longer passes cleanup checks: \(url.path)"
    }
  }
}

private struct GitCommandRunner {
  func run(_ arguments: [String], in directory: URL) throws -> String {
    let output = try runData(arguments, in: directory)
    return String(decoding: output, as: UTF8.self)
      .trimmingCharacters(in: .newlines)
  }

  func runData(_ arguments: [String], in directory: URL) throws -> Data {
    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()

    process.executableURL = URL(filePath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    try process.run()
    let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      throw GitCommandError(
        arguments: arguments,
        directory: directory,
        terminationStatus: process.terminationStatus,
        standardError: String(decoding: error, as: UTF8.self)
      )
    }

    return output
  }
}

private struct GitCommandError: LocalizedError {
  let arguments: [String]
  let directory: URL
  let terminationStatus: Int32
  let standardError: String

  var errorDescription: String? {
    let command = (["git"] + arguments).joined(separator: " ")
    let details = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
    return "\(command) failed in \(directory.path) with status "
      + "\(terminationStatus): \(details)"
  }
}

private struct DiskUsageMeasurer {
  private let resourceKeys: Set<URLResourceKey> = [
    .fileAllocatedSizeKey,
    .fileSizeKey,
    .isDirectoryKey,
    .isRegularFileKey,
    .isSymbolicLinkKey,
    .totalFileAllocatedSizeKey,
  ]

  func allocatedSize(
    of directory: URL,
    excludingImmediateGitEntry: Bool = false
  ) throws -> Int64 {
    var scanError: Error?
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: Array(resourceKeys),
        errorHandler: { _, error in
          scanError = error
          return false
        }
      )
    else {
      throw GitWorkspaceError.cannotMeasureDiskUsage(directory)
    }

    let excludedGitPath =
      excludingImmediateGitEntry
      ? directory.appending(path: ".git").standardizedFileURL.path : nil
    var total: Int64 = 0

    while let entry = enumerator.nextObject() as? URL {
      try Task.checkCancellation()
      let values = try entry.resourceValues(forKeys: resourceKeys)

      if entry.standardizedFileURL.path == excludedGitPath {
        if values.isDirectory == true {
          enumerator.skipDescendants()
        }
        continue
      }
      if values.isSymbolicLink == true {
        enumerator.skipDescendants()
        continue
      }
      guard values.isRegularFile == true else { continue }

      let allocatedBytes =
        values.totalFileAllocatedSize
        ?? values.fileAllocatedSize
        ?? values.fileSize
        ?? 0
      total += Int64(allocatedBytes)
    }

    if let scanError {
      throw scanError
    }
    return total
  }
}

private func canonicalURL(_ url: URL) -> URL {
  let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
  return URL(filePath: resolved.path, directoryHint: .isDirectory)
}
