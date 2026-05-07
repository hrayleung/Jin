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

        Menu("Count") {
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

        Menu("Size") {
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

        if !availableQualities.isEmpty {
            Menu("Quality") {
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
        }

        if showsStyle {
            Menu("Style") {
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
        }

        if !availableBackgrounds.isEmpty {
            Menu("Background") {
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
        }

        if showsOutputFormat {
            Menu("Output Format") {
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
        }

        if showsOutputFormat, (currentOutputFormat == .jpeg || currentOutputFormat == .webp) {
            Menu("Compression") {
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
        }

        if showsModeration {
            Menu("Moderation") {
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
        }

        if showsInputFidelity {
            Menu("Input Fidelity") {
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
        }

        if isConfigured {
            Divider()
            Button("Reset", role: .destructive, action: onReset)
        }
    }
}
