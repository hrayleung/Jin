import SwiftUI

struct XAIImageGenerationMenuView<MenuItemLabel: View>: View {
    let isConfigured: Bool
    let currentCount: Int?
    let selectedAspectRatio: XAIAspectRatio?
    let menuItemLabel: (String, Bool) -> MenuItemLabel
    let onSetCount: (Int?) -> Void
    let onSetAspectRatio: (XAIAspectRatio?) -> Void
    let onReset: () -> Void

    var body: some View {
        Text("xAI Image")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        Menu("Count") {
            Button {
                onSetCount(nil)
            } label: {
                menuItemLabel("Default", currentCount == nil)
            }
            ForEach([1, 2, 4], id: \.self) { count in
                Button {
                    onSetCount(count)
                } label: {
                    menuItemLabel("\(count)", currentCount == count)
                }
            }
        }

        Menu("Aspect ratio") {
            Button {
                onSetAspectRatio(nil)
            } label: {
                menuItemLabel("Default", selectedAspectRatio == nil)
            }
            ForEach(XAIAspectRatio.allCases, id: \.self) { ratio in
                Button {
                    onSetAspectRatio(ratio)
                } label: {
                    menuItemLabel(ratio.displayName, selectedAspectRatio == ratio)
                }
            }
        }

        if isConfigured {
            Divider()
            Button("Reset", role: .destructive, action: onReset)
        }
    }
}
