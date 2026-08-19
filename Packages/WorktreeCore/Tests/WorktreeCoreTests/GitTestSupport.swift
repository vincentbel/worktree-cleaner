import Foundation

func makeTemporaryDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
  try FileManager.default.createDirectory(
    at: directory,
    withIntermediateDirectories: true
  )
  return directory
}

func makeRepositoryWithLinkedWorktree() throws -> (
  base: URL,
  repository: URL,
  linkedWorktree: URL
) {
  let baseDirectory = try makeTemporaryDirectory()
  let repositoryDirectory = baseDirectory.appending(path: "project")
  let linkedWorktreeDirectory = baseDirectory.appending(path: "project-agent")
  try FileManager.default.createDirectory(
    at: repositoryDirectory,
    withIntermediateDirectories: true
  )
  try runGit(
    ["init", "--quiet", "--initial-branch", "main"],
    in: repositoryDirectory
  )
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
  return (baseDirectory, repositoryDirectory, linkedWorktreeDirectory)
}

func runGit(_ arguments: [String], in directory: URL) throws {
  let process = Process()
  let errorPipe = Pipe()
  process.executableURL = URL(filePath: "/usr/bin/git")
  process.arguments = arguments
  process.currentDirectoryURL = directory
  process.standardError = errorPipe

  try process.run()
  process.waitUntilExit()

  guard process.terminationStatus == 0 else {
    let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
    let message = String(decoding: data, as: UTF8.self)
    throw TestGitError.commandFailed(arguments: arguments, message: message)
  }
}

enum TestGitError: Error {
  case commandFailed(arguments: [String], message: String)
}
