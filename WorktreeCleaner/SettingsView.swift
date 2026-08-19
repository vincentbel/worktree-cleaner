import Sparkle
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
  let model: AppState
  let updater: SPUUpdater

  var body: some View {
    TabView {
      DirectorySettingsView(model: model)
        .tabItem {
          Label(L10n.string("settings.directories.tab"), systemImage: "folder")
        }

      UpdateSettingsView(updater: updater)
        .tabItem {
          Label(L10n.string("settings.updates.tab"), systemImage: "arrow.triangle.2.circlepath")
        }
    }
    .frame(width: 680, height: 420)
  }
}

private struct DirectorySettingsView: View {
  let model: AppState

  @State private var isChoosingDirectory = false

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
          Text(L10n.string("directory_manager.title"))
            .font(.title2.weight(.semibold))
          Text(L10n.string("settings.directories.description"))
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button(L10n.string("toolbar.add_directory"), systemImage: "plus") {
          isChoosingDirectory = true
        }
      }
      .padding()

      Divider()

      if model.workspaceRoots.urls.isEmpty {
        ContentUnavailableView(
          L10n.string("directory_manager.empty.title"),
          systemImage: "folder.badge.plus",
          description: Text(L10n.string("directory_manager.empty.description"))
        )
      } else {
        List(model.workspaceRoots.urls, id: \.self) { rootURL in
          HStack(spacing: 12) {
            Image(systemName: "folder")
              .font(.title3)
              .foregroundStyle(.secondary)
              .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
              Text(rootURL.lastPathComponent)
                .fontWeight(.medium)
              Text(rootURL.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
                .help(rootURL.path)
            }

            Spacer(minLength: 16)

            DirectoryScanStatus(model: model, rootURL: rootURL)

            Text(
              L10n.plural(
                "directory_manager.repository_count",
                count: model.repositoryCount(under: rootURL)
              )
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(minWidth: 72, alignment: .trailing)

            Button(
              L10n.string("directory_manager.remove"),
              systemImage: "trash",
              role: .destructive
            ) {
              Task { await model.removeDirectory(rootURL) }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help(L10n.string("directory_manager.remove_help"))
          }
          .padding(.vertical, 5)
        }
      }
    }
    .fileImporter(
      isPresented: $isChoosingDirectory,
      allowedContentTypes: [.folder],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else {
        if case .failure(let error) = result {
          model.errorMessage = error.localizedDescription
        }
        return
      }
      Task { await model.addDirectory(url) }
    }
    .alert(
      L10n.string("alert.operation_failed"),
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: { if !$0 { model.errorMessage = nil } }
      )
    ) {
      Button(L10n.string("common.ok"), role: .cancel) {}
    } message: {
      Text(model.errorMessage ?? L10n.string("error.unknown"))
    }
  }
}

private struct DirectoryScanStatus: View {
  let model: AppState
  let rootURL: URL

  var body: some View {
    if model.isScanning(rootURL) {
      Label {
        Text(L10n.string("directory_manager.scanning"))
      } icon: {
        ProgressView()
          .controlSize(.small)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    } else if let error = model.scanError(for: rootURL) {
      Label(
        L10n.string("directory_manager.scan_failed"),
        systemImage: "exclamationmark.triangle.fill"
      )
      .font(.caption)
      .foregroundStyle(.orange)
      .help(error)
    }
  }
}

private struct UpdateSettingsView: View {
  private let updater: SPUUpdater

  @State private var automaticallyChecksForUpdates: Bool
  @State private var automaticallyDownloadsUpdates: Bool

  init(updater: SPUUpdater) {
    self.updater = updater
    self._automaticallyChecksForUpdates = State(
      initialValue: updater.automaticallyChecksForUpdates
    )
    self._automaticallyDownloadsUpdates = State(
      initialValue: updater.automaticallyDownloadsUpdates
    )
  }

  var body: some View {
    Form {
      Section {
        Toggle(
          L10n.string("settings.updates.automatic_check"),
          isOn: $automaticallyChecksForUpdates
        )
        .onChange(of: automaticallyChecksForUpdates) { _, newValue in
          updater.automaticallyChecksForUpdates = newValue
        }

        Toggle(
          L10n.string("settings.updates.automatic_download"),
          isOn: $automaticallyDownloadsUpdates
        )
        .disabled(!automaticallyChecksForUpdates)
        .onChange(of: automaticallyDownloadsUpdates) { _, newValue in
          updater.automaticallyDownloadsUpdates = newValue
        }
      } header: {
        Text(L10n.string("settings.updates.title"))
      } footer: {
        Text(L10n.string("settings.updates.description"))
      }

      Section {
        CheckForUpdatesView(updater: updater)
      }
    }
    .formStyle(.grouped)
    .padding()
  }
}
