import SwiftUI

struct XAIImageGenerationMenuView: View {
    let isConfigured: Bool
    let supportsResolution: Bool
    let supportsQuality: Bool
    let currentCount: Int?
    let selectedAspectRatio: XAIAspectRatio?
    let currentResolution: XAIImageResolution?
    let currentQuality: XAIImageQuality?
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
            JinMenuSelectionItem("Default", isSelected: currentCount == nil) {
                onSetCount(nil)
            }
            ForEach([1, 2, 4], id: \.self) { count in
                JinMenuSelectionItem("\(count)", isSelected: currentCount == count) {
                    onSetCount(count)
                }
            }
        }
        .id("xai-image-count-\(currentCount.map(String.init) ?? "default")")

        Menu(aspectMenuTitle) {
            JinMenuSelectionItem("Default", isSelected: selectedAspectRatio == nil) {
                onSetAspectRatio(nil)
            }
            ForEach(XAIAspectRatio.allCases, id: \.self) { ratio in
                JinMenuSelectionItem(ratio.displayName, isSelected: selectedAspectRatio == ratio) {
                    onSetAspectRatio(ratio)
                }
            }
        }
        .id("xai-image-aspect-\(selectedAspectRatio?.rawValue ?? "default")")

        if supportsResolution {
            Menu(resolutionMenuTitle) {
                JinMenuSelectionItem("Default", isSelected: currentResolution == nil) {
                    onSetResolution(nil)
                }
                ForEach(XAIImageResolution.allCases, id: \.self) { resolution in
                    JinMenuSelectionItem(resolution.displayName, isSelected: currentResolution == resolution) {
                        onSetResolution(resolution)
                    }
                }
            }
            .id("xai-image-resolution-\(currentResolution?.rawValue ?? "default")")
        }

        if supportsQuality {
            Menu(qualityMenuTitle) {
                JinMenuSelectionItem("Default", isSelected: currentQuality == nil) {
                    onSetQuality(nil)
                }
                ForEach(XAIModelSupport.image2QualityOptions, id: \.self) { quality in
                    JinMenuSelectionItem(quality.displayName, isSelected: currentQuality == quality) {
                        onSetQuality(quality)
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
