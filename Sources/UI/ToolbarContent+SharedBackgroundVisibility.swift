import SwiftUI

extension ToolbarContent {
    @ToolbarContentBuilder
    func jinHideSharedBackgroundIfAvailable() -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

