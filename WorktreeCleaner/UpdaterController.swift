import Combine
import Sparkle
import SwiftUI

@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
  @Published var canCheckForUpdates = false

  init(updater: SPUUpdater) {
    updater.publisher(for: \.canCheckForUpdates)
      .assign(to: &$canCheckForUpdates)
  }
}

struct CheckForUpdatesView: View {
  @ObservedObject private var model: CheckForUpdatesViewModel
  private let updater: SPUUpdater

  init(updater: SPUUpdater) {
    self.updater = updater
    self.model = CheckForUpdatesViewModel(updater: updater)
  }

  var body: some View {
    Button(L10n.string("app.check_for_updates"), action: updater.checkForUpdates)
      .disabled(!model.canCheckForUpdates)
  }
}
