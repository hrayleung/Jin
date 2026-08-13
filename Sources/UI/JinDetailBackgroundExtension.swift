import SwiftUI

/// macOS 26+ wrapper for `backgroundExtensionEffect()`. On older OSes the
/// modifier is a no-op so the detail view's background does not extend
/// into the safe-area region behind the floating sidebar. Lets detail-side
/// colours flow under the Tahoe Liquid Glass sidebar without breaking the
/// macOS 14/15 layout.
struct JinDetailBackgroundExtension: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // Apple's effect *duplicates* the view it is attached to and
            // mirrors the copy into the under-sidebar safe area. Attaching
            // it to the live chat tree (NSTableView of hosted markdown)
            // remakes that tree every time the sidebar slides — empty
            // detail is cheap, an open conversation is not. Extend only
            // the flat surface tint, which is what Landmarks / HIG show.
            content.background {
                JinSemanticColor.detailSurface
                    .ignoresSafeArea()
                    .backgroundExtensionEffect()
            }
        } else {
            content
        }
    }
}
