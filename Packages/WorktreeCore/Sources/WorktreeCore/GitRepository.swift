import Foundation

public struct GitRepository: Identifiable, Hashable, Sendable {
  public var id: URL { commonGitDirectoryURL }
  public var name: String { workingTreeURL.lastPathComponent }

  public let workingTreeURL: URL
  public let commonGitDirectoryURL: URL
  public let linkedWorktreeCount: Int

  init(
    workingTreeURL: URL,
    commonGitDirectoryURL: URL,
    linkedWorktreeCount: Int
  ) {
    self.workingTreeURL = workingTreeURL
    self.commonGitDirectoryURL = commonGitDirectoryURL
    self.linkedWorktreeCount = linkedWorktreeCount
  }
}
