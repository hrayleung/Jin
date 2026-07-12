import SwiftUI

struct GoogleVideoGenerationMenuView<MenuItemLabel: View>: View {
    let isVeo3: Bool
    let availableResolutions: [GoogleVideoResolution]
    let isVertexProvider: Bool
    let isConfigured: Bool
    let currentDurationSeconds: Int?
    let currentAspectRatio: GoogleVideoAspectRatio?
    let currentResolution: GoogleVideoResolution?
    let currentPersonGeneration: GoogleVideoPersonGeneration?
    let generateAudioBinding: Binding<Bool>
    let menuItemLabel: (String, Bool) -> MenuItemLabel
    let onSetDurationSeconds: (Int?) -> Void
    let onSetAspectRatio: (GoogleVideoAspectRatio?) -> Void
    let onSetResolution: (GoogleVideoResolution?) -> Void
    let onSetPersonGeneration: (GoogleVideoPersonGeneration?) -> Void
    let onReset: () -> Void

    var body: some View {
        Text("Google Veo")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        Menu("Duration") {
            Button {
                onSetDurationSeconds(nil)
            } label: {
                menuItemLabel("Default", currentDurationSeconds == nil)
            }
            ForEach([4, 6, 8], id: \.self) { seconds in
                Button {
                    onSetDurationSeconds(seconds)
                } label: {
                    menuItemLabel("\(seconds)s", currentDurationSeconds == seconds)
                }
            }
        }

        Menu("Aspect ratio") {
            Button {
                onSetAspectRatio(nil)
            } label: {
                menuItemLabel("Default (16:9)", currentAspectRatio == nil)
            }
            ForEach(GoogleVideoAspectRatio.allCases, id: \.self) { ratio in
                Button {
                    onSetAspectRatio(ratio)
                } label: {
                    menuItemLabel(ratio.displayName, currentAspectRatio == ratio)
                }
            }
        }

        if isVeo3 {
            Menu("Resolution") {
                Button {
                    onSetResolution(nil)
                } label: {
                    menuItemLabel("Default (720p)", currentResolution == nil)
                }
                ForEach(availableResolutions, id: \.self) { resolution in
                    Button {
                        onSetResolution(resolution)
                    } label: {
                        menuItemLabel(resolution.displayName, currentResolution == resolution)
                    }
                }
            }
        }

        Menu("Person generation") {
            Button {
                onSetPersonGeneration(nil)
            } label: {
                menuItemLabel("Default", currentPersonGeneration == nil)
            }
            ForEach(GoogleVideoPersonGeneration.allCases, id: \.self) { personGeneration in
                Button {
                    onSetPersonGeneration(personGeneration)
                } label: {
                    menuItemLabel(personGeneration.displayName, currentPersonGeneration == personGeneration)
                }
            }
        }

        if isVertexProvider, isVeo3 {
            Toggle("Generate audio", isOn: generateAudioBinding)
        }

        if isConfigured {
            Divider()
            Button("Reset", role: .destructive, action: onReset)
        }
    }
}

struct XAIVideoGenerationMenuView<MenuItemLabel: View>: View {
    let isConfigured: Bool
    let currentMode: XAIVideoMode
    let currentDuration: Int?
    let currentAspectRatio: XAIAspectRatio?
    let currentResolution: XAIVideoResolution?
    let availableModes: [XAIVideoMode]
    let availableResolutions: [XAIVideoResolution]
    let showsDuration: Bool
    let showsAspectAndResolution: Bool
    let durationOptions: [Int]
    let durationHelpLabel: String
    let menuItemLabel: (String, Bool) -> MenuItemLabel
    /// Always receive a concrete mode (including `.auto`) so selection can persist + show checkmarks.
    let onSetMode: (XAIVideoMode) -> Void
    let onSetDuration: (Int?) -> Void
    let onSetAspectRatio: (XAIAspectRatio?) -> Void
    let onSetResolution: (XAIVideoResolution?) -> Void
    let onReset: () -> Void

    var body: some View {
        Text("xAI Video")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        // Title includes the active mode so the choice is visible even before opening the submenu.
        Menu("Mode · \(currentMode.displayName)") {
            ForEach(availableModes, id: \.self) { mode in
                Button {
                    onSetMode(mode)
                } label: {
                    // Leading checkmark is the reliable macOS menu selection affordance;
                    // trailing Spacer checkmarks are easy to miss / collapse in nested menus.
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .opacity(mode == currentMode ? 1 : 0)
                            .frame(width: 14, alignment: .center)
                        Text(mode.displayName)
                    }
                }
            }
        }
        // Force the submenu to rebuild when mode changes so the checkmark updates on re-open.
        .id("xai-video-mode-\(currentMode.rawValue)")

        if showsDuration {
            Menu(durationMenuTitle) {
                Button {
                    onSetDuration(nil)
                } label: {
                    menuItemLabel(durationHelpLabel, currentDuration == nil)
                }
                ForEach(durationOptions, id: \.self) { seconds in
                    Button {
                        onSetDuration(seconds)
                    } label: {
                        menuItemLabel("\(seconds)s", currentDuration == seconds)
                    }
                }
            }
        }

        if showsAspectAndResolution {
            Menu(aspectMenuTitle) {
                Button {
                    onSetAspectRatio(nil)
                } label: {
                    menuItemLabel("Default (16:9)", currentAspectRatio == nil)
                }
                ForEach(
                    [XAIAspectRatio.ratio1x1, .ratio16x9, .ratio9x16, .ratio4x3, .ratio3x4, .ratio3x2, .ratio2x3],
                    id: \.self
                ) { ratio in
                    Button {
                        onSetAspectRatio(ratio)
                    } label: {
                        menuItemLabel(ratio.displayName, currentAspectRatio == ratio)
                    }
                }
            }

            Menu(resolutionMenuTitle) {
                Button {
                    onSetResolution(nil)
                } label: {
                    menuItemLabel("Default (480p)", currentResolution == nil)
                }
                ForEach(availableResolutions, id: \.self) { resolution in
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

    private var durationMenuTitle: String {
        if let currentDuration {
            return "Duration · \(currentDuration)s"
        }
        return "Duration"
    }

    private var aspectMenuTitle: String {
        if let currentAspectRatio {
            return "Aspect ratio · \(currentAspectRatio.displayName)"
        }
        return "Aspect ratio"
    }

    private var resolutionMenuTitle: String {
        if let currentResolution {
            return "Resolution · \(currentResolution.displayName)"
        }
        return "Resolution"
    }
}

struct OpenRouterVideoGenerationMenuView<MenuItemLabel: View>: View {
    let isConfigured: Bool
    let supportedDurations: [Int]
    let supportedAspectRatios: [OpenRouterVideoAspectRatio]
    let supportedResolutions: [OpenRouterVideoResolution]
    let currentDurationSeconds: Int?
    let currentAspectRatio: OpenRouterVideoAspectRatio?
    let currentResolution: OpenRouterVideoResolution?
    let currentImageInputMode: OpenRouterVideoImageInputMode?
    let showsAudioToggle: Bool
    let showsWatermarkToggle: Bool
    let generateAudioBinding: Binding<Bool>
    let watermarkBinding: Binding<Bool>
    let menuItemLabel: (String, Bool) -> MenuItemLabel
    let onSetDurationSeconds: (Int?) -> Void
    let onSetAspectRatio: (OpenRouterVideoAspectRatio?) -> Void
    let onSetResolution: (OpenRouterVideoResolution?) -> Void
    let onSetImageInputMode: (OpenRouterVideoImageInputMode?) -> Void
    let onReset: () -> Void

    var body: some View {
        Text("OpenRouter Video")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        Menu("Duration") {
            Button {
                onSetDurationSeconds(nil)
            } label: {
                menuItemLabel("Default", currentDurationSeconds == nil)
            }
            ForEach(supportedDurations, id: \.self) { seconds in
                Button {
                    onSetDurationSeconds(seconds)
                } label: {
                    menuItemLabel("\(seconds)s", currentDurationSeconds == seconds)
                }
            }
        }

        Menu("Aspect ratio") {
            Button {
                onSetAspectRatio(nil)
            } label: {
                menuItemLabel("Default", currentAspectRatio == nil)
            }
            ForEach(supportedAspectRatios, id: \.self) { ratio in
                Button {
                    onSetAspectRatio(ratio)
                } label: {
                    menuItemLabel(ratio.displayName, currentAspectRatio == ratio)
                }
            }
        }

        Menu("Resolution") {
            Button {
                onSetResolution(nil)
            } label: {
                menuItemLabel("Default", currentResolution == nil)
            }
            ForEach(supportedResolutions, id: \.self) { resolution in
                Button {
                    onSetResolution(resolution)
                } label: {
                    menuItemLabel(resolution.displayName, currentResolution == resolution)
                }
            }
        }

        Menu("Image mode") {
            Button {
                onSetImageInputMode(nil)
            } label: {
                menuItemLabel("Default (Smart)", currentImageInputMode == nil)
            }
            ForEach(OpenRouterVideoImageInputMode.allCases, id: \.self) { mode in
                Button {
                    onSetImageInputMode(mode)
                } label: {
                    menuItemLabel(mode.displayName, currentImageInputMode == mode)
                }
            }
        }

        if showsAudioToggle {
            Toggle("Generate audio", isOn: generateAudioBinding)
        }

        if showsWatermarkToggle {
            Toggle("Watermark", isOn: watermarkBinding)
        }

        if isConfigured {
            Divider()
            Button("Reset", role: .destructive, action: onReset)
        }
    }
}
