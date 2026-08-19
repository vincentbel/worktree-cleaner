import Foundation

public struct GitRepository: Identifiable, Hashable, Sendable {
  public var id: URL { commonGitDirectoryURL }
  public var name: String { workingTreeURL.lastPathComponent }

  public let workingTreeURL: URL
  public let commonGitDirectoryURL: URL

  init(workingTreeURL: URL, commonGitDirectoryURL: URL) {
    self.workingTreeURL = workingTreeURL
    self.commonGitDirectoryURL = commonGitDirectoryURL
  }
}
