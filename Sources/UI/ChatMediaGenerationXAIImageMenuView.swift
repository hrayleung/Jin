import SwiftUI

struct XAIImageGenerationMenuView<MenuItemLabel: View>: View {
    let isConfigured: Bool
    let supportsResolution: Bool
    let supportsQuality: Bool
    let currentCount: Int?
    let selectedAspectRatio: XAIAspectRatio?
    let currentResolution: XAIImageResolution?
    let currentQuality: XAIImageQuality?
    let menuItemLabel: (String, Bool) -> MenuItemLabel
    let onSetCount: (Int?) -> Void
    let onSetAspectRatio: (XAIAspectRatio?) -> Void
    let onSetResolution: (XAIImageResolution?) -> Void
    let onSetQuality: (XAIImageQuality?) -> Void
    let onReset: () -> Void

    var body: some View {
        Text("xAI Image")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        Menu(countMenuTitle) {
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
        .id("xai-image-count-\(currentCount.map(String.init) ?? "default")")

        Menu(aspectMenuTitle) {
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
        .id("xai-image-aspect-\(selectedAspectRatio?.rawValue ?? "default")")

        if supportsResolution {
            Menu(resolutionMenuTitle) {
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
            .id("xai-image-resolution-\(currentResolution?.rawValue ?? "default")")
        }

        if supportsQuality {
            Menu(qualityMenuTitle) {
                Button {
                    onSetQuality(nil)
                } label: {
                    menuItemLabel("Default", currentQuality == nil)
                }
                ForEach(XAIModelSupport.image2QualityOptions, id: \.self) { quality in
                    Button {
                        onSetQuality(quality)
                    } label: {
                        menuItemLabel(quality.displayName, currentQuality == quality)
                    }
                }
            }
            .id("xai-image-quality-\(currentQuality?.rawValue ?? "default")")
        }

        if isConfigured {
            Divider()
            Button("Reset", role: .destructive, action: onReset)
        }
    }

    private var countMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Count",
            current: currentCount.map(String.init)
        )
    }

    private var aspectMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Aspect ratio",
            current: selectedAspectRatio?.displayName
        )
    }

    private var resolutionMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Resolution",
            current: currentResolution?.displayName
        )
    }

    private var qualityMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Quality",
            current: currentQuality?.displayName
        )
    }
}
