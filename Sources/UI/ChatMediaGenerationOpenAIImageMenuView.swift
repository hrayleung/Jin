import SwiftUI

struct OpenAIImageGenerationMenuView<MenuItemLabel: View>: View {
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
    let menuItemLabel: (String, Bool) -> MenuItemLabel
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
            Button {
                onSetCount(nil)
            } label: {
                menuItemLabel("Default (1)", currentCount == nil)
            }
            ForEach([1, 2, 4], id: \.self) { count in
                Button {
                    onSetCount(count)
                } label: {
                    menuItemLabel("\(count)", currentCount == count)
                }
            }
        }
        .id("openai-image-count-\(currentCount.map(String.init) ?? "default")")

        Menu(sizeMenuTitle) {
            Button {
                onSetSize(nil)
            } label: {
                menuItemLabel("Default", currentSize == nil)
            }
            ForEach(availableSizes, id: \.self) { size in
                Button {
                    onSetSize(size)
                } label: {
                    menuItemLabel(size.displayName, currentSize == size)
                }
            }

            if supportsCustomSizeEditor {
                Divider()
                Button {
                    onShowCustomSizeEditor()
                } label: {
                    let title = currentSizeIsCustom ? "Custom (\(currentSize?.displayName ?? ""))…" : "Custom…"
                    menuItemLabel(title, currentSizeIsCustom)
                }
            }
        }
        .id("openai-image-size-\(currentSize?.rawValue ?? "default")")

        if !availableQualities.isEmpty {
            Menu(qualityMenuTitle) {
                Button {
                    onSetQuality(nil)
                } label: {
                    menuItemLabel("Default", currentQuality == nil)
                }
                ForEach(availableQualities, id: \.self) { quality in
                    Button {
                        onSetQuality(quality)
                    } label: {
                        menuItemLabel(quality.displayName, currentQuality == quality)
                    }
                }
            }
            .id("openai-image-quality-\(currentQuality?.rawValue ?? "default")")
        }

        if showsStyle {
            Menu(styleMenuTitle) {
                Button {
                    onSetStyle(nil)
                } label: {
                    menuItemLabel("Default (Vivid)", currentStyle == nil)
                }
                ForEach(OpenAIImageStyle.allCases, id: \.self) { style in
                    Button {
                        onSetStyle(style)
                    } label: {
                        menuItemLabel(style.displayName, currentStyle == style)
                    }
                }
            }
            .id("openai-image-style-\(currentStyle?.rawValue ?? "default")")
        }

        if !availableBackgrounds.isEmpty {
            Menu(backgroundMenuTitle) {
                Button {
                    onSetBackground(nil)
                } label: {
                    menuItemLabel("Default (Auto)", currentBackground == nil)
                }
                ForEach(availableBackgrounds, id: \.self) { background in
                    Button {
                        onSetBackground(background)
                    } label: {
                        menuItemLabel(background.displayName, currentBackground == background)
                    }
                }
            }
            .id("openai-image-background-\(currentBackground?.rawValue ?? "default")")
        }

        if showsOutputFormat {
            Menu(outputFormatMenuTitle) {
                Button {
                    onSetOutputFormat(nil)
                } label: {
                    menuItemLabel("Default (PNG)", currentOutputFormat == nil)
                }
                ForEach(OpenAIImageOutputFormat.allCases, id: \.self) { format in
                    Button {
                        onSetOutputFormat(format)
                    } label: {
                        menuItemLabel(format.displayName, currentOutputFormat == format)
                    }
                }
            }
            .id("openai-image-output-format-\(currentOutputFormat?.rawValue ?? "default")")
        }

        if showsOutputFormat, (currentOutputFormat == .jpeg || currentOutputFormat == .webp) {
            Menu(compressionMenuTitle) {
                Button {
                    onSetOutputCompression(nil)
                } label: {
                    menuItemLabel("Default (100)", currentOutputCompression == nil)
                }
                ForEach([25, 50, 75, 100], id: \.self) { level in
                    Button {
                        onSetOutputCompression(level)
                    } label: {
                        menuItemLabel("\(level)%", currentOutputCompression == level)
                    }
                }
            }
            .id("openai-image-compression-\(currentOutputCompression.map(String.init) ?? "default")")
        }

        if showsModeration {
            Menu(moderationMenuTitle) {
                Button {
                    onSetModeration(nil)
                } label: {
                    menuItemLabel("Default (Auto)", currentModeration == nil)
                }
                ForEach(OpenAIImageModeration.allCases, id: \.self) { moderation in
                    Button {
                        onSetModeration(moderation)
                    } label: {
                        menuItemLabel(moderation.displayName, currentModeration == moderation)
                    }
                }
            }
            .id("openai-image-moderation-\(currentModeration?.rawValue ?? "default")")
        }

        if showsInputFidelity {
            Menu(inputFidelityMenuTitle) {
                Button {
                    onSetInputFidelity(nil)
                } label: {
                    menuItemLabel("Default (Low)", currentInputFidelity == nil)
                }
                ForEach(OpenAIImageInputFidelity.allCases, id: \.self) { fidelity in
                    Button {
                        onSetInputFidelity(fidelity)
                    } label: {
                        menuItemLabel(fidelity.displayName, currentInputFidelity == fidelity)
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
