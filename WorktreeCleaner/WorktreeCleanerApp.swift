import AppKit
import Sparkle
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  #if DEBUG
    func applicationDidFinishLaunching(_ notification: Notification) {
      if DemoLaunch.directoryURL != nil {
        NSApp.appearance = NSAppearance(named: .aqua)
      }
    }
  #endif

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }
}

@main
struct WorktreeCleanerApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var model: AppState

  private let updaterController: SPUStandardUpdaterController

  init() {
    #if DEBUG
      let demoDirectoryURL = DemoLaunch.directoryURL
      _model = State(initialValue: AppState(demoDirectoryURL: demoDirectoryURL))
      let startingUpdater = demoDirectoryURL == nil
    #else
      _model = State(initialValue: AppState())
      let startingUpdater = true
    #endif
    updaterController = SPUStandardUpdaterController(
      startingUpdater: startingUpdater,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
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

#if DEBUG
  private enum DemoLaunch {
    static let directoryURL: URL? = {
      let arguments = ProcessInfo.processInfo.arguments
      guard let index = arguments.firstIndex(of: "--demo-directory") else { return nil }
      let valueIndex = arguments.index(after: index)
      precondition(
        valueIndex < arguments.endIndex && !arguments[valueIndex].hasPrefix("-"),
        "Expected a directory path after --demo-directory"
      )
      return URL(filePath: arguments[valueIndex], directoryHint: .isDirectory)
    }()
  }
#endif
