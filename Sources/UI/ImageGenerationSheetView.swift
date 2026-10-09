import SwiftUI

struct ImageGenerationSheetView: View {
    @Binding var draft: ImageGenerationControls
    @Binding var seedDraft: String
    @Binding var compressionQualityDraft: String
    @Binding var draftError: String?

    let providerType: ProviderType?
    let supportsImageSizeControl: Bool
    let supportedAspectRatios: [ImageAspectRatio]
    let supportedImageSizes: [ImageOutputSize]
    let isValid: Bool

    var onCancel: () -> Void
    var onSave: () -> Bool

    var body: some View {
        JinSheet("Image Generation") {
            JinSettingsPage(horizontalPadding: 0, verticalPadding: 0) {
                outputSection
                if providerType == .vertexai {
                    vertexSection
                }
                errorSection
            }
        } actions: {
            Button("Cancel") { onCancel() }
                .keyboardShortcut(.cancelAction)

            Button("Save") {
                if onSave() {
                    onCancel()
                }
            }
            .disabled(!isValid)
            .keyboardShortcut(.defaultAction)
        }
        .frame(width: 520, height: providerType == .vertexai ? 600 : 420)
    }

    // MARK: - Sections

    private var outputSection: some View {
        JinSettingsSection("Output") {
            Picker(
                "Response",
                selection: Binding(
                    get: { draft.responseMode ?? .textAndImage },
                    set: { value in
                        draft.responseMode = (value == .textAndImage) ? nil : value
                    }
                )
            ) {
                ForEach(ImageResponseMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            if !supportedAspectRatios.isEmpty {
                Picker("Aspect Ratio", selection: $draft.aspectRatio) {
                    Text("Default").tag(Optional<ImageAspectRatio>.none)
                    ForEach(supportedAspectRatios, id: \.self) { ratio in
                        Text(ratio.displayName).tag(Optional(ratio))
                    }
                }
            }

            if supportsImageSizeControl {
                Picker("Image Size", selection: $draft.imageSize) {
                    Text("Default").tag(Optional<ImageOutputSize>.none)
                    ForEach(supportedImageSizes, id: \.self) { size in
                        Text(size.displayName).tag(Optional(size))
                    }
                }
            }

            JinSettingsTextFieldRow("Seed", prompt: "Optional", text: $seedDraft, usesMonospacedFont: true)
        }
    }

    private var vertexSection: some View {
        JinSettingsSection("Vertex") {
            Picker("Person generation", selection: $draft.vertexPersonGeneration) {
                Text("Default").tag(Optional<VertexImagePersonGeneration>.none)
                ForEach(VertexImagePersonGeneration.allCases, id: \.self) { item in
                    Text(item.displayName).tag(Optional(item))
                }
            }

            Picker("Output MIME", selection: $draft.vertexOutputMIMEType) {
                Text("Default").tag(Optional<VertexImageOutputMIMEType>.none)
                ForEach(VertexImageOutputMIMEType.allCases, id: \.self) { item in
                    Text(item.displayName).tag(Optional(item))
                }
            }

            JinSettingsTextFieldRow(
                "JPEG Quality", prompt: "0–100, optional",
                text: $compressionQualityDraft,
                usesMonospacedFont: true
            )
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let draftError {
            Section {
                JinSettingsErrorText(text: draftError)
            }
        }
    }
}
