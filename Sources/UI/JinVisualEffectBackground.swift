import SwiftUI
#if os(macOS)
import AppKit
#endif

/// NSVisualEffectView-backed background that follows the window's active state.
///
/// We need this because:
///   - `Color(NSColor.windowBackgroundColor)` does NOT dim when the window loses
///     key focus — it only varies with light/dark appearance. So a solid color
///     sidebar produces a visible discontinuity with the title bar (which DOES
///     dim) when the user opens Settings or another window steals focus.
///   - `.background(.regularMaterial)` (and the system's automatic `.sidebar`
///     material on NavigationSplitView) skews too light/translucent for Jin's
///     dark detail surface, producing a "glass sidebar over matte detail"
///     contrast the user finds jarring.
///
/// `.windowBackground` material is the same tone as the system window
/// background (≈ NSColor.windowBackgroundColor) and dims uniformly with the
/// title bar via `.followsWindowActiveState`. Result: sidebar visually
/// matches the detail pane AND dims continuously with the rest of the chrome.
struct JinVisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .windowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        if nsView.material != material { nsView.material = material }
        if nsView.blendingMode != blendingMode { nsView.blendingMode = blendingMode }
    }
}
