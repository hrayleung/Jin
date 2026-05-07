import SwiftUI

struct OpenAIImageCustomSizeSheetView: View {
    @State private var draftText: String
    @State private var validationError: String?
    @Environment(\.dismiss) private var dismiss

    let modelID: String
    let currentSize: OpenAIImageSize?
    var onCancel: () -> Void
    var onSave: (OpenAIImageSize) -> Void

    init(
        modelID: String,
        currentSize: OpenAIImageSize?,
        onCancel: @escaping () -> Void,
        onSave: @escaping (OpenAIImageSize) -> Void
    ) {
        self.modelID = modelID
        self.currentSize = currentSize
        self.onCancel = onCancel
        self.onSave = onSave

        _draftText = State(
            initialValue: OpenAIImageCustomSizeSheetSupport.initialDraftText(currentSize: currentSize)
        )
    }

    private var parsedSize: OpenAIImageSize? {
        OpenAIImageCustomSizeSheetSupport.parsedSize(from: draftText)
    }

    private var currentValidationError: String? {
        OpenAIImageCustomSizeSheetSupport.validationError(draftText: draftText, modelID: modelID)
    }

    private var displayedValidationError: String? {
        OpenAIImageCustomSizeSheetSupport.displayedValidationError(
            explicitError: validationError,
            draftText: draftText,
            modelID: modelID
        )
    }

    private var canSubmit: Bool {
        OpenAIImageCustomSizeSheetSupport.canSubmit(draftText: draftText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Custom Size") {
                    JinSettingsTextField("2048x1152", text: $draftText, usesMonospacedFont: true)
                        .onChange(of: draftText) { _, _ in
                            validationError = nil
                        }

                    Text(OpenAIImageModelSupport.sizeConstraintSummary(for: modelID))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let validationError = displayedValidationError {
                    Section {
                        JinSettingsErrorText(text: validationError)
                    }
                }
            }
            .navigationTitle("Custom Size")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let parsedSize else {
                            validationError = OpenAIImageCustomSizeSheetSupport.invalidSizeMessage
                            return
                        }
                        if let error = currentValidationError {
                            validationError = error
                            return
                        }
                        onSave(parsedSize)
                        dismiss()
                    }
                    .disabled(!canSubmit)
                }
            }
        }
        .frame(width: 520)
    }
}
