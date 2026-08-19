import Foundation

public enum WorkspaceRootError: Error, Equatable, Sendable {
  case duplicate(URL)
  case overlaps(existing: URL)
}

public struct WorkspaceRoots: Equatable, Sendable {
  public private(set) var urls: [URL]

  public init() {
    self.urls = []
  }

  public init(_ urls: [URL]) throws {
    self.urls = []
    for url in urls {
      try add(url)
    }
  }

  public mutating func add(_ url: URL) throws {
    let normalizedURL = Self.normalize(url)
    for existingURL in urls {
      if existingURL == normalizedURL {
        throw WorkspaceRootError.duplicate(existingURL)
      }
      if Self.contains(existingURL, normalizedURL)
        || Self.contains(normalizedURL, existingURL)
      {
        throw WorkspaceRootError.overlaps(existing: existingURL)
      }
    }
    urls.append(normalizedURL)
  }

  public mutating func remove(_ url: URL) {
    let normalizedURL = Self.normalize(url)
    urls.removeAll { $0 == normalizedURL }
  }

  public static func normalize(_ url: URL) -> URL {
    URL(
      filePath: url.standardizedFileURL.resolvingSymlinksInPath().path,
      directoryHint: .isDirectory
    )
  }

  private static func contains(_ parent: URL, _ child: URL) -> Bool {
    let parentComponents = parent.pathComponents
    let childComponents = child.pathComponents
    guard parentComponents.count < childComponents.count else { return false }
    return childComponents.starts(with: parentComponents)
  }
}
