import SwiftUI

/// macOS 26+ wrapper for `backgroundExtensionEffect()`. On older OSes the
/// modifier is a no-op so the detail view's background does not extend
/// into the safe-area region behind the floating sidebar. Lets detail-side
/// colours flow under the Tahoe Liquid Glass sidebar without breaking the
/// macOS 14/15 layout.
struct JinDetailBackgroundExtension: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.backgroundExtensionEffect()
        } else {
            content
        }
    }
}
