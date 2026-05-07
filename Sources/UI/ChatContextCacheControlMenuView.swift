import SwiftUI

struct ContextCacheControlMenuView<MenuItemLabel: View>: View {
    let effectiveMode: ContextCacheMode
    let supportsExplicitContextCacheMode: Bool
    let showsReset: Bool
    let onTurnOff: () -> Void
    let onSetImplicit: () -> Void
    let onSetExplicit: () -> Void
    let onConfigure: () -> Void
    let onReset: () -> Void
    let menuItemLabel: (String, Bool) -> MenuItemLabel

    var body: some View {
        Button(action: onTurnOff) {
            menuItemLabel("Off", effectiveMode == .off)
        }

        Button(action: onSetImplicit) {
            menuItemLabel("Implicit", effectiveMode == .implicit)
        }

        if supportsExplicitContextCacheMode {
            Button(action: onSetExplicit) {
                menuItemLabel("Explicit", effectiveMode == .explicit)
            }
        }

        Divider()

        Button("Configure…", action: onConfigure)

        if showsReset {
            Divider()
            Button("Reset", role: .destructive, action: onReset)
        }
    }
}
