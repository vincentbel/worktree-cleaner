import AppKit
import Foundation

struct OpenTarget: Identifiable {
  enum Action {
    case application(URL)
    case finder
  }

  let id: String
  let label: String
  let icon: NSImage
  let action: Action
}

@MainActor
struct OpenTargetService {
  func availableTargets() -> [OpenTarget] {
    Self.detectedTargets
  }

  func copyPath(_ url: URL) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.path, forType: .string)
  }

  func open(_ url: URL, with target: OpenTarget) async throws {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw OpenTargetError.missingPath(url)
    }

    switch target.action {
    case .finder:
      guard NSWorkspace.shared.open(url) else {
        throw OpenTargetError.cannotOpen(url, target.label)
      }
    case .application(let applicationURL):
      let configuration = NSWorkspace.OpenConfiguration()
      try await NSWorkspace.shared.open(
        [url],
        withApplicationAt: applicationURL,
        configuration: configuration
      )
    }
  }

  private static func firstExistingApplication(in paths: [String]) -> URL? {
    let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    for path in paths {
      var candidates = [URL(filePath: path, directoryHint: .isDirectory)]
      if path.hasPrefix("/Applications/") {
        candidates.append(
          homeDirectory.appending(path: "Applications/\(path.dropFirst("/Applications/".count))")
        )
      }
      if let applicationURL = candidates.first(where: {
        FileManager.default.fileExists(atPath: $0.path)
      }) {
        return applicationURL
      }
    }
    return nil
  }

  private struct Definition {
    let id: String
    let label: String
    let applicationPaths: [String]
    var isFinder = false
  }

  private static let definitions: [Definition] = [
    Definition(
      id: "vscode",
      label: "VS Code",
      applicationPaths: [
        "/Applications/Visual Studio Code.app",
        "/Applications/Code.app",
      ]
    ),
    Definition(
      id: "cursor",
      label: "Cursor",
      applicationPaths: ["/Applications/Cursor.app"]
    ),
    Definition(
      id: "antigravity",
      label: "Antigravity",
      applicationPaths: ["/Applications/Antigravity.app"]
    ),
    Definition(
      id: "zed",
      label: "Zed",
      applicationPaths: ["/Applications/Zed.app"]
    ),
    Definition(
      id: "trae",
      label: "Trae",
      applicationPaths: ["/Applications/Trae.app"]
    ),
    Definition(
      id: "trae-cn",
      label: "Trae CN",
      applicationPaths: ["/Applications/Trae CN.app"]
    ),
    Definition(
      id: "finder",
      label: "Finder",
      applicationPaths: ["/System/Library/CoreServices/Finder.app"],
      isFinder: true
    ),
    Definition(
      id: "terminal",
      label: "Terminal",
      applicationPaths: ["/System/Applications/Utilities/Terminal.app"]
    ),
    Definition(
      id: "iterm2",
      label: "iTerm2",
      applicationPaths: [
        "/Applications/iTerm.app",
        "/Applications/iTerm2.app",
      ]
    ),
    Definition(
      id: "ghostty",
      label: "Ghostty",
      applicationPaths: ["/Applications/Ghostty.app"]
    ),
    Definition(
      id: "xcode",
      label: "Xcode",
      applicationPaths: ["/Applications/Xcode.app"]
    ),
  ]

  private static let detectedTargets: [OpenTarget] = definitions.compactMap { definition in
    guard let applicationURL = firstExistingApplication(in: definition.applicationPaths)
    else { return nil }
    let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
    icon.size = NSSize(width: 20, height: 20)
    let label =
      switch definition.id {
      case "finder": L10n.string("open_target.finder")
      case "terminal": L10n.string("open_target.terminal")
      default: definition.label
      }
    return OpenTarget(
      id: definition.id,
      label: label,
      icon: icon,
      action: definition.isFinder ? .finder : .application(applicationURL)
    )
  }
}

private enum OpenTargetError: LocalizedError {
  case cannotOpen(URL, String)
  case missingPath(URL)

  var errorDescription: String? {
    switch self {
    case .cannotOpen(let url, let target):
      L10n.format("error.cannot_open_target", url.path, target)
    case .missingPath(let url):
      L10n.format("error.open_path_missing", url.path)
    }
  }
}
