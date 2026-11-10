import AppKit
import SwiftUI
import WorktreeCore

struct AgentProjectIcon: View {
  let application: AgentApplication
  let projects: [AgentProject]

  var body: some View {
    AgentProjectImage(image: image, projectHelp: help)
      .frame(width: 16, height: 16)
      .accessibilityLabel(L10n.format("project.association.label", applicationName))
      .accessibilityValue(help)
  }

  private var applicationName: String {
    switch application {
    case .codex: "Codex"
    case .claudeCode: "Claude Code"
    }
  }

  private var help: String {
    let bindings = projects.map {
      L10n.format("project.association.binding", $0.name, $0.path.path)
    }.joined(separator: "\n")
    return L10n.format("project.association.help", applicationName, bindings)
  }

  private var image: NSImage? {
    if let icon = Self.installedIcons[application] {
      return icon
    }
    return NSImage(named: application == .codex ? "CodexProject" : "ClaudeCodeProject")
  }

  private static let installedIcons: [AgentApplication: NSImage] = {
    let identifiers: [AgentApplication: String] = [
      .codex: "com.openai.codex",
      .claudeCode: "com.anthropic.claudefordesktop",
    ]
    var icons: [AgentApplication: NSImage] = [:]
    for (application, identifier) in identifiers {
      if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
        icons[application] = NSWorkspace.shared.icon(forFile: url.path)
      }
    }
    return icons
  }()
}

private struct AgentProjectImage: NSViewRepresentable {
  let image: NSImage?
  let projectHelp: String

  func makeNSView(context: Context) -> ProjectIconView {
    let view = ProjectIconView()
    view.clipsToBounds = true
    view.imageScaling = .scaleProportionallyUpOrDown
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    return view
  }

  func updateNSView(_ view: ProjectIconView, context: Context) {
    view.image = image
    view.projectHelp = projectHelp
  }

  static func dismantleNSView(_ view: ProjectIconView, coordinator: ()) {
    view.hideHelp()
  }

  final class ProjectIconView: NSImageView {
    var projectHelp = "" {
      didSet {
        if projectHelp != oldValue, popover.isShown {
          updateHelpContent()
        }
      }
    }

    private var hoverArea: NSTrackingArea?
    private let popover: NSPopover = {
      let popover = NSPopover()
      popover.behavior = .transient
      popover.animates = false
      return popover
    }()

    override func updateTrackingAreas() {
      if let hoverArea { removeTrackingArea(hoverArea) }
      let area = NSTrackingArea(
        rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
        owner: self, userInfo: nil)
      addTrackingArea(area)
      hoverArea = area
      super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
      guard window != nil, !popover.isShown else { return }
      updateHelpContent()
      popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
    }

    override func mouseExited(with event: NSEvent) {
      hideHelp()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
      if newWindow == nil { hideHelp() }
      super.viewWillMove(toWindow: newWindow)
    }

    func hideHelp() {
      popover.close()
    }

    private func updateHelpContent() {
      let label = NSTextField(wrappingLabelWithString: projectHelp)
      label.font = .systemFont(ofSize: NSFont.systemFontSize)
      label.preferredMaxLayoutWidth = 336
      label.frame = NSRect(x: 12, y: 12, width: 336, height: label.intrinsicContentSize.height)
      let controller = NSViewController()
      controller.view = NSView(
        frame: NSRect(x: 0, y: 0, width: 360, height: label.frame.height + 24))
      controller.view.addSubview(label)
      popover.contentViewController = controller
      popover.contentSize = controller.view.frame.size
    }
  }
}
