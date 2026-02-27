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
        NavigationStack {
            Form {
                outputSection
                if providerType == .vertexai {
                    vertexSection
                }
                errorSection
            }
            .navigationTitle("Image Generation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if onSave() {
                            onCancel()
                        }
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(width: 500)
    }

    // MARK: - Sections

    private var outputSection: some View {
        Section("Output") {
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

            Picker("Aspect Ratio", selection: $draft.aspectRatio) {
                Text("Default").tag(Optional<ImageAspectRatio>.none)
                ForEach(supportedAspectRatios, id: \.self) { ratio in
                    Text(ratio.displayName).tag(Optional(ratio))
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

            TextField("Seed (optional)", text: $seedDraft)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
        }
    }

    private var vertexSection: some View {
        Section("Vertex") {
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

            TextField("JPEG quality 0-100 (optional)", text: $compressionQualityDraft)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let draftError {
            Section {
                Text(draftError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }
}
