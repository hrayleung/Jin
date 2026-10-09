import SwiftUI

struct GoogleVideoGenerationMenuView: View {
    let productLabel: String
    let showsDuration: Bool
    let showsPersonGeneration: Bool
    let availableAspectRatios: [GoogleVideoAspectRatio]
    let availableResolutions: [GoogleVideoResolution]
    let showsGenerateAudio: Bool
    let isConfigured: Bool
    let currentDurationSeconds: Int?
    let currentAspectRatio: GoogleVideoAspectRatio?
    let currentResolution: GoogleVideoResolution?
    let currentPersonGeneration: GoogleVideoPersonGeneration?
    let generateAudioBinding: Binding<Bool>
    let onSetDurationSeconds: (Int?) -> Void
    let onSetAspectRatio: (GoogleVideoAspectRatio?) -> Void
    let onSetResolution: (GoogleVideoResolution?) -> Void
    let onSetPersonGeneration: (GoogleVideoPersonGeneration?) -> Void
    let onReset: () -> Void

    var body: some View {
        Text(productLabel)
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        if showsDuration {
            Menu(durationMenuTitle) {
                JinMenuSelectionItem("Default", isSelected: currentDurationSeconds == nil) {
                    onSetDurationSeconds(nil)
                }
                ForEach([4, 6, 8], id: \.self) { seconds in
                    JinMenuSelectionItem("\(seconds)s", isSelected: currentDurationSeconds == seconds) {
                        onSetDurationSeconds(seconds)
                    }
                }
            }
            .id("google-video-duration-\(currentDurationSeconds.map(String.init) ?? "default")")
        }

        Menu(aspectMenuTitle) {
            JinMenuSelectionItem("Default (16:9)", isSelected: currentAspectRatio == nil) {
                onSetAspectRatio(nil)
            }
            ForEach(availableAspectRatios, id: \.self) { ratio in
                JinMenuSelectionItem(ratio.displayName, isSelected: currentAspectRatio == ratio) {
                    onSetAspectRatio(ratio)
                }
            }
        }
        .id("google-video-aspect-\(currentAspectRatio?.rawValue ?? "default")")

        if !availableResolutions.isEmpty {
            Menu(resolutionMenuTitle) {
                JinMenuSelectionItem("Default (720p)", isSelected: currentResolution == nil) {
                    onSetResolution(nil)
                }
                ForEach(availableResolutions, id: \.self) { resolution in
                    JinMenuSelectionItem(resolution.displayName, isSelected: currentResolution == resolution) {
                        onSetResolution(resolution)
                    }
                }
            }
            .id("google-video-resolution-\(currentResolution?.rawValue ?? "default")")
        }

        if showsPersonGeneration {
            Menu(personGenerationMenuTitle) {
                JinMenuSelectionItem("Default", isSelected: currentPersonGeneration == nil) {
                    onSetPersonGeneration(nil)
                }
                ForEach(GoogleVideoPersonGeneration.allCases, id: \.self) { personGeneration in
                    JinMenuSelectionItem(
                        personGeneration.displayName,
                        isSelected: currentPersonGeneration == personGeneration
                    ) {
                        onSetPersonGeneration(personGeneration)
                    }
                }
            }
            .id("google-video-person-\(currentPersonGeneration?.rawValue ?? "default")")
        }

        if showsGenerateAudio {
            Toggle("Generate audio", isOn: generateAudioBinding)
        }

        if isConfigured {
            Divider()
            Button("Reset", role: .destructive, action: onReset)
        }
    }

    private var durationMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Duration",
            current: currentDurationSeconds.map { "\($0)s" }
        )
    }

    private var aspectMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Aspect ratio",
            current: currentAspectRatio?.displayName
        )
    }

    private var resolutionMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Resolution",
            current: currentResolution?.displayName
        )
    }

    private var personGenerationMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Person generation",
            current: currentPersonGeneration?.displayName
        )
    }
}

struct XAIVideoGenerationMenuView: View {
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
        Menu(ChatAuxiliaryControlSupport.nestedMenuTitle("Mode", current: currentMode.displayName)) {
            ForEach(availableModes, id: \.self) { mode in
                JinMenuSelectionItem(mode.displayName, isSelected: mode == currentMode) {
                    onSetMode(mode)
                }
            }
        }
        // Force the submenu to rebuild when mode changes so the checkmark updates on re-open.
        .id("xai-video-mode-\(currentMode.rawValue)")

        if showsDuration {
            Menu(durationMenuTitle) {
                JinMenuSelectionItem(durationHelpLabel, isSelected: currentDuration == nil) {
                    onSetDuration(nil)
                }
                ForEach(durationOptions, id: \.self) { seconds in
                    JinMenuSelectionItem("\(seconds)s", isSelected: currentDuration == seconds) {
                        onSetDuration(seconds)
                    }
                }
            }
            .id("xai-video-duration-\(currentDuration.map(String.init) ?? "default")")
        }

        if showsAspectAndResolution {
            Menu(aspectMenuTitle) {
                JinMenuSelectionItem("Default (16:9)", isSelected: currentAspectRatio == nil) {
                    onSetAspectRatio(nil)
                }
                ForEach(
                    [XAIAspectRatio.ratio1x1, .ratio16x9, .ratio9x16, .ratio4x3, .ratio3x4, .ratio3x2, .ratio2x3],
                    id: \.self
                ) { ratio in
                    JinMenuSelectionItem(ratio.displayName, isSelected: currentAspectRatio == ratio) {
                        onSetAspectRatio(ratio)
                    }
                }
            }
            .id("xai-video-aspect-\(currentAspectRatio?.rawValue ?? "default")")

            Menu(resolutionMenuTitle) {
                JinMenuSelectionItem("Default (480p)", isSelected: currentResolution == nil) {
                    onSetResolution(nil)
                }
                ForEach(availableResolutions, id: \.self) { resolution in
                    JinMenuSelectionItem(resolution.displayName, isSelected: currentResolution == resolution) {
                        onSetResolution(resolution)
                    }
                }
            }
            .id("xai-video-resolution-\(currentResolution?.rawValue ?? "default")")
        }

        if isConfigured {
            Divider()
            Button("Reset", role: .destructive, action: onReset)
        }
    }

    private var durationMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Duration",
            current: currentDuration.map { "\($0)s" }
        )
    }

    private var aspectMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Aspect ratio",
            current: currentAspectRatio?.displayName
        )
    }

    private var resolutionMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Resolution",
            current: currentResolution?.displayName
        )
    }
}

struct OpenRouterVideoGenerationMenuView: View {
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

        Menu(durationMenuTitle) {
            JinMenuSelectionItem("Default", isSelected: currentDurationSeconds == nil) {
                onSetDurationSeconds(nil)
            }
            ForEach(supportedDurations, id: \.self) { seconds in
                JinMenuSelectionItem("\(seconds)s", isSelected: currentDurationSeconds == seconds) {
                    onSetDurationSeconds(seconds)
                }
            }
        }
        .id("openrouter-video-duration-\(currentDurationSeconds.map(String.init) ?? "default")")

        Menu(aspectMenuTitle) {
            JinMenuSelectionItem("Default", isSelected: currentAspectRatio == nil) {
                onSetAspectRatio(nil)
            }
            ForEach(supportedAspectRatios, id: \.self) { ratio in
                JinMenuSelectionItem(ratio.displayName, isSelected: currentAspectRatio == ratio) {
                    onSetAspectRatio(ratio)
                }
            }
        }
        .id("openrouter-video-aspect-\(currentAspectRatio?.rawValue ?? "default")")

        Menu(resolutionMenuTitle) {
            JinMenuSelectionItem("Default", isSelected: currentResolution == nil) {
                onSetResolution(nil)
            }
            ForEach(supportedResolutions, id: \.self) { resolution in
                JinMenuSelectionItem(resolution.displayName, isSelected: currentResolution == resolution) {
                    onSetResolution(resolution)
                }
            }
        }
        .id("openrouter-video-resolution-\(currentResolution?.rawValue ?? "default")")

        Menu(imageModeMenuTitle) {
            JinMenuSelectionItem("Default (Smart)", isSelected: currentImageInputMode == nil) {
                onSetImageInputMode(nil)
            }
            ForEach(OpenRouterVideoImageInputMode.allCases, id: \.self) { mode in
                JinMenuSelectionItem(mode.displayName, isSelected: currentImageInputMode == mode) {
                    onSetImageInputMode(mode)
                }
            }
        }
        .id("openrouter-video-image-mode-\(currentImageInputMode?.rawValue ?? "default")")

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

    private var durationMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Duration",
            current: currentDurationSeconds.map { "\($0)s" }
        )
    }

    private var aspectMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Aspect ratio",
            current: currentAspectRatio?.displayName
        )
    }

    private var resolutionMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Resolution",
            current: currentResolution?.displayName
        )
    }

    private var imageModeMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Image mode",
            current: currentImageInputMode?.displayName
        )
    }
}

struct TogetherVideoGenerationMenuView: View {
    let isConfigured: Bool
    let supportedDurations: [Int]
    let supportedAspectRatios: [TogetherVideoAspectRatio]
    let supportedResolutions: [TogetherVideoResolution]
    let currentDurationSeconds: Int?
    let currentAspectRatio: TogetherVideoAspectRatio?
    let currentResolution: TogetherVideoResolution?
    let currentImageInputMode: TogetherVideoImageInputMode?
    let showsAudioToggle: Bool
    let generateAudioBinding: Binding<Bool>
    let onSetDurationSeconds: (Int?) -> Void
    let onSetAspectRatio: (TogetherVideoAspectRatio?) -> Void
    let onSetResolution: (TogetherVideoResolution?) -> Void
    let onSetImageInputMode: (TogetherVideoImageInputMode?) -> Void
    let onReset: () -> Void

    var body: some View {
        Text("Together Video")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        Menu(durationMenuTitle) {
            JinMenuSelectionItem("Default", isSelected: currentDurationSeconds == nil) {
                onSetDurationSeconds(nil)
            }
            ForEach(supportedDurations, id: \.self) { seconds in
                JinMenuSelectionItem("\(seconds)s", isSelected: currentDurationSeconds == seconds) {
                    onSetDurationSeconds(seconds)
                }
            }
        }
        .id("together-video-duration-\(currentDurationSeconds.map(String.init) ?? "default")")

        Menu(aspectMenuTitle) {
            JinMenuSelectionItem("Default", isSelected: currentAspectRatio == nil) {
                onSetAspectRatio(nil)
            }
            ForEach(supportedAspectRatios, id: \.self) { ratio in
                JinMenuSelectionItem(ratio.displayName, isSelected: currentAspectRatio == ratio) {
                    onSetAspectRatio(ratio)
                }
            }
        }
        .id("together-video-aspect-\(currentAspectRatio?.rawValue ?? "default")")

        Menu(resolutionMenuTitle) {
            JinMenuSelectionItem("Default", isSelected: currentResolution == nil) {
                onSetResolution(nil)
            }
            ForEach(supportedResolutions, id: \.self) { resolution in
                JinMenuSelectionItem(resolution.displayName, isSelected: currentResolution == resolution) {
                    onSetResolution(resolution)
                }
            }
        }
        .id("together-video-resolution-\(currentResolution?.rawValue ?? "default")")

        Menu(imageModeMenuTitle) {
            JinMenuSelectionItem("Default (Smart)", isSelected: currentImageInputMode == nil) {
                onSetImageInputMode(nil)
            }
            ForEach(TogetherVideoImageInputMode.allCases, id: \.self) { mode in
                JinMenuSelectionItem(mode.displayName, isSelected: currentImageInputMode == mode) {
                    onSetImageInputMode(mode)
                }
            }
        }
        .id("together-video-image-mode-\(currentImageInputMode?.rawValue ?? "default")")

        if showsAudioToggle {
            Toggle("Generate audio", isOn: generateAudioBinding)
        }

        if isConfigured {
            Divider()
            Button("Reset", role: .destructive, action: onReset)
        }
    }

    private var durationMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Duration",
            current: currentDurationSeconds.map { "\($0)s" }
        )
    }

    private var aspectMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Aspect ratio",
            current: currentAspectRatio?.displayName
        )
    }

    private var resolutionMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Resolution",
            current: currentResolution?.displayName
        )
    }

    private var imageModeMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Image mode",
            current: currentImageInputMode?.displayName
        )
    }
}
