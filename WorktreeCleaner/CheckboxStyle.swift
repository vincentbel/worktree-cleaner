import AppKit
import SwiftUI

extension View {
  func clearDisabledCheckboxStyle() -> some View {
    modifier(ClearDisabledCheckboxStyle())
  }
}

private struct ClearDisabledCheckboxStyle: ViewModifier {
  @Environment(\.isEnabled) private var isEnabled

  func body(content: Content) -> some View {
    content
      .toggleStyle(.checkbox)
      .opacity(isEnabled ? 1 : 0.55)
      .overlay {
        if !isEnabled {
          DisabledCheckboxCursorRegion()
        }
      }
  }
}

private struct DisabledCheckboxCursorRegion: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    CursorRegionView()
  }

  func updateNSView(_ view: NSView, context: Context) {}

  private final class CursorRegionView: NSView {
    override func resetCursorRects() {
      super.resetCursorRects()
      addCursorRect(bounds, cursor: .operationNotAllowed)
    }
  }
}
