import SwiftUI

struct OpenAIImageGenerationMenuView: View {
    let isConfigured: Bool
    let availableSizes: [OpenAIImageSize]
    let supportsCustomSizeEditor: Bool
    let availableQualities: [OpenAIImageQuality]
    let showsStyle: Bool
    let availableBackgrounds: [OpenAIImageBackground]
    let showsOutputFormat: Bool
    let showsModeration: Bool
    let showsInputFidelity: Bool
    let currentCount: Int?
    let currentSize: OpenAIImageSize?
    let currentQuality: OpenAIImageQuality?
    let currentStyle: OpenAIImageStyle?
    let currentBackground: OpenAIImageBackground?
    let currentOutputFormat: OpenAIImageOutputFormat?
    let currentOutputCompression: Int?
    let currentModeration: OpenAIImageModeration?
    let currentInputFidelity: OpenAIImageInputFidelity?
    let onSetCount: (Int?) -> Void
    let onSetSize: (OpenAIImageSize?) -> Void
    let onShowCustomSizeEditor: () -> Void
    let onSetQuality: (OpenAIImageQuality?) -> Void
    let onSetStyle: (OpenAIImageStyle?) -> Void
    let onSetBackground: (OpenAIImageBackground?) -> Void
    let onSetOutputFormat: (OpenAIImageOutputFormat?) -> Void
    let onSetOutputCompression: (Int?) -> Void
    let onSetModeration: (OpenAIImageModeration?) -> Void
    let onSetInputFidelity: (OpenAIImageInputFidelity?) -> Void
    let onReset: () -> Void

    private var currentSizeIsCustom: Bool {
        guard let currentSize else { return false }
        return currentSize.isAuto == false && !availableSizes.contains(currentSize)
    }

    var body: some View {
        Text("OpenAI Image")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        Menu(countMenuTitle) {
            JinMenuSelectionItem("Default (1)", isSelected: currentCount == nil) {
                onSetCount(nil)
            }
            ForEach([1, 2, 4], id: \.self) { count in
                JinMenuSelectionItem("\(count)", isSelected: currentCount == count) {
                    onSetCount(count)
                }
            }
        }
        .id("openai-image-count-\(currentCount.map(String.init) ?? "default")")

        Menu(sizeMenuTitle) {
            JinMenuSelectionItem("Default", isSelected: currentSize == nil) {
                onSetSize(nil)
            }
            ForEach(availableSizes, id: \.self) { size in
                JinMenuSelectionItem(size.displayName, isSelected: currentSize == size) {
                    onSetSize(size)
                }
            }

            if supportsCustomSizeEditor {
                Divider()
                let title = currentSizeIsCustom ? "Custom (\(currentSize?.displayName ?? ""))…" : "Custom…"
                JinMenuSelectionItem(title, isSelected: currentSizeIsCustom) {
                    onShowCustomSizeEditor()
                }
            }
        }
        .id("openai-image-size-\(currentSize?.rawValue ?? "default")")

        if !availableQualities.isEmpty {
            Menu(qualityMenuTitle) {
                JinMenuSelectionItem("Default", isSelected: currentQuality == nil) {
                    onSetQuality(nil)
                }
                ForEach(availableQualities, id: \.self) { quality in
                    JinMenuSelectionItem(quality.displayName, isSelected: currentQuality == quality) {
                        onSetQuality(quality)
                    }
                }
            }
            .id("openai-image-quality-\(currentQuality?.rawValue ?? "default")")
        }

        if showsStyle {
            Menu(styleMenuTitle) {
                JinMenuSelectionItem("Default (Vivid)", isSelected: currentStyle == nil) {
                    onSetStyle(nil)
                }
                ForEach(OpenAIImageStyle.allCases, id: \.self) { style in
                    JinMenuSelectionItem(style.displayName, isSelected: currentStyle == style) {
                        onSetStyle(style)
                    }
                }
            }
            .id("openai-image-style-\(currentStyle?.rawValue ?? "default")")
        }

        if !availableBackgrounds.isEmpty {
            Menu(backgroundMenuTitle) {
                JinMenuSelectionItem("Default (Auto)", isSelected: currentBackground == nil) {
                    onSetBackground(nil)
                }
                ForEach(availableBackgrounds, id: \.self) { background in
                    JinMenuSelectionItem(background.displayName, isSelected: currentBackground == background) {
                        onSetBackground(background)
                    }
                }
            }
            .id("openai-image-background-\(currentBackground?.rawValue ?? "default")")
        }

        if showsOutputFormat {
            Menu(outputFormatMenuTitle) {
                JinMenuSelectionItem("Default (PNG)", isSelected: currentOutputFormat == nil) {
                    onSetOutputFormat(nil)
                }
                ForEach(OpenAIImageOutputFormat.allCases, id: \.self) { format in
                    JinMenuSelectionItem(format.displayName, isSelected: currentOutputFormat == format) {
                        onSetOutputFormat(format)
                    }
                }
            }
            .id("openai-image-output-format-\(currentOutputFormat?.rawValue ?? "default")")
        }

        if showsOutputFormat, (currentOutputFormat == .jpeg || currentOutputFormat == .webp) {
            Menu(compressionMenuTitle) {
                JinMenuSelectionItem("Default (100)", isSelected: currentOutputCompression == nil) {
                    onSetOutputCompression(nil)
                }
                ForEach([25, 50, 75, 100], id: \.self) { level in
                    JinMenuSelectionItem("\(level)%", isSelected: currentOutputCompression == level) {
                        onSetOutputCompression(level)
                    }
                }
            }
            .id("openai-image-compression-\(currentOutputCompression.map(String.init) ?? "default")")
        }

        if showsModeration {
            Menu(moderationMenuTitle) {
                JinMenuSelectionItem("Default (Auto)", isSelected: currentModeration == nil) {
                    onSetModeration(nil)
                }
                ForEach(OpenAIImageModeration.allCases, id: \.self) { moderation in
                    JinMenuSelectionItem(moderation.displayName, isSelected: currentModeration == moderation) {
                        onSetModeration(moderation)
                    }
                }
            }
            .id("openai-image-moderation-\(currentModeration?.rawValue ?? "default")")
        }

        if showsInputFidelity {
            Menu(inputFidelityMenuTitle) {
                JinMenuSelectionItem("Default (Low)", isSelected: currentInputFidelity == nil) {
                    onSetInputFidelity(nil)
                }
                ForEach(OpenAIImageInputFidelity.allCases, id: \.self) { fidelity in
                    JinMenuSelectionItem(fidelity.displayName, isSelected: currentInputFidelity == fidelity) {
                        onSetInputFidelity(fidelity)
                    }
                }
            }
            .id("openai-image-input-fidelity-\(currentInputFidelity?.rawValue ?? "default")")
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

    private var sizeMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Size",
            current: currentSizeIsCustom
                ? "Custom (\(currentSize?.displayName ?? ""))"
                : currentSize?.displayName
        )
    }

    private var qualityMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Quality",
            current: currentQuality?.displayName
        )
    }

    private var styleMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Style",
            current: currentStyle?.displayName
        )
    }

    private var backgroundMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Background",
            current: currentBackground?.displayName
        )
    }

    private var outputFormatMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Output Format",
            current: currentOutputFormat?.displayName
        )
    }

    private var compressionMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Compression",
            current: currentOutputCompression.map { "\($0)%" }
        )
    }

    private var moderationMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Moderation",
            current: currentModeration?.displayName
        )
    }

    private var inputFidelityMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Input Fidelity",
            current: currentInputFidelity?.displayName
        )
    }
}
