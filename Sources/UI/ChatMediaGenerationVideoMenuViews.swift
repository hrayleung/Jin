import SwiftUI

struct GoogleVideoGenerationMenuView<MenuItemLabel: View>: View {
    let isVeo3: Bool
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
                ForEach(GoogleVideoResolution.allCases, id: \.self) { resolution in
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
    let currentDuration: Int?
    let currentAspectRatio: XAIAspectRatio?
    let currentResolution: XAIVideoResolution?
    let menuItemLabel: (String, Bool) -> MenuItemLabel
    let onSetDuration: (Int?) -> Void
    let onSetAspectRatio: (XAIAspectRatio?) -> Void
    let onSetResolution: (XAIVideoResolution?) -> Void
    let onReset: () -> Void

    var body: some View {
        Text("xAI Video")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        Menu("Duration") {
            Button {
                onSetDuration(nil)
            } label: {
                menuItemLabel("Default (8s)", currentDuration == nil)
            }
            ForEach([3, 5, 8, 10, 15], id: \.self) { seconds in
                Button {
                    onSetDuration(seconds)
                } label: {
                    menuItemLabel("\(seconds)s", currentDuration == seconds)
                }
            }
        }

        Menu("Aspect ratio") {
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

        Menu("Resolution") {
            Button {
                onSetResolution(nil)
            } label: {
                menuItemLabel("Default (480p)", currentResolution == nil)
            }
            ForEach(XAIVideoResolution.allCases, id: \.self) { resolution in
                Button {
                    onSetResolution(resolution)
                } label: {
                    menuItemLabel(resolution.displayName, currentResolution == resolution)
                }
            }
        }

        if isConfigured {
            Divider()
            Button("Reset", role: .destructive, action: onReset)
        }
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
