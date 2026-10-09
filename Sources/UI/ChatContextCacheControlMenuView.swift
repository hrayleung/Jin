import SwiftUI

struct ContextCacheControlMenuView: View {
    let effectiveMode: ContextCacheMode
    let supportsExplicitContextCacheMode: Bool
    let showsReset: Bool
    let onTurnOff: () -> Void
    let onSetImplicit: () -> Void
    let onSetExplicit: () -> Void
    let onConfigure: () -> Void
    let onReset: () -> Void

    var body: some View {
        JinMenuSelectionItem("Off", isSelected: effectiveMode == .off, action: onTurnOff)

        JinMenuSelectionItem("Implicit", isSelected: effectiveMode == .implicit, action: onSetImplicit)

        if supportsExplicitContextCacheMode {
            JinMenuSelectionItem("Explicit", isSelected: effectiveMode == .explicit, action: onSetExplicit)
        }

        Divider()

        Button("Configure…", action: onConfigure)

        if showsReset {
            Divider()
            Button("Reset", role: .destructive, action: onReset)
        }
    }
}
