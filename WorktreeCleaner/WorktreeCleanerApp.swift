import Sparkle
import SwiftUI

@main
struct WorktreeCleanerApp: App {
  @State private var model = AppState()

  private let updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
  )

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
