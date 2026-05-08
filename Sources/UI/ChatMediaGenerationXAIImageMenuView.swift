import SwiftUI

struct XAIImageGenerationMenuView<MenuItemLabel: View>: View {
    let isConfigured: Bool
    let supportsResolution: Bool
    let currentCount: Int?
    let selectedAspectRatio: XAIAspectRatio?
    let currentResolution: XAIImageResolution?
    let menuItemLabel: (String, Bool) -> MenuItemLabel
    let onSetCount: (Int?) -> Void
    let onSetAspectRatio: (XAIAspectRatio?) -> Void
    let onSetResolution: (XAIImageResolution?) -> Void
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

        if supportsResolution {
            Menu("Resolution") {
                Button {
                    onSetResolution(nil)
                } label: {
                    menuItemLabel("Default", currentResolution == nil)
                }
                ForEach(XAIImageResolution.allCases, id: \.self) { resolution in
                    Button {
                        onSetResolution(resolution)
                    } label: {
                        menuItemLabel(resolution.displayName, currentResolution == resolution)
                    }
                }
            }
        }

        if isConfigured {
            Divider()
            Button("Reset", role: .destructive, action: onReset)
        }
    }
}
