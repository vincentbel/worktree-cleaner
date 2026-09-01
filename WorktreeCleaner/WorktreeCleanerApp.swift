import AppKit
import Sparkle
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }
}

@main
struct WorktreeCleanerApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var model: AppState

  private let updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
  )

  init() {
    let arguments = ProcessInfo.processInfo.arguments
    let demoDirectoryURL: URL?
    if let index = arguments.firstIndex(of: "--demo-directory") {
      let valueIndex = arguments.index(after: index)
      demoDirectoryURL =
        valueIndex < arguments.endIndex
        ? URL(filePath: arguments[valueIndex], directoryHint: .isDirectory)
        : nil
    } else {
      demoDirectoryURL = nil
    }
    _model = State(initialValue: AppState(demoDirectoryURL: demoDirectoryURL))
  }

  var body: some Scene {
    WindowGroup {
      ContentView(model: model)
    }
    .defaultSize(width: 1_100, height: 720)
    .commands {
      CommandGroup(after: .appInfo) {
        CheckForUpdatesView(updater: updaterController.updater)
      }
    }

    Settings {
      SettingsView(model: model, updater: updaterController.updater)
    }
  }
}
