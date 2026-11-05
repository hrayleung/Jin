import SwiftUI

struct OpenAIImageCustomSizeSheetView: View {
    @State private var draftText: String
    @State private var validationError: String?
    @Environment(\.dismiss) private var dismiss

    let modelID: String
    let currentSize: OpenAIImageSize?
    let outputFormat: OpenAIImageOutputFormat?
    var onCancel: () -> Void
    var onSave: (OpenAIImageSize) -> Void

    init(
        modelID: String,
        currentSize: OpenAIImageSize?,
        outputFormat: OpenAIImageOutputFormat? = nil,
        onCancel: @escaping () -> Void,
        onSave: @escaping (OpenAIImageSize) -> Void
    ) {
        self.modelID = modelID
        self.currentSize = currentSize
        self.outputFormat = outputFormat
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
        OpenAIImageCustomSizeSheetSupport.validationError(draftText: draftText, modelID: modelID, outputFormat: outputFormat)
    }

    private var displayedValidationError: String? {
        OpenAIImageCustomSizeSheetSupport.displayedValidationError(
            explicitError: validationError,
            draftText: draftText,
            modelID: modelID,
            outputFormat: outputFormat
        )
    }

    private var canSubmit: Bool {
        OpenAIImageCustomSizeSheetSupport.canSubmit(draftText: draftText)
    }

    var body: some View {
        JinSheet("Custom Size") {
            JinSettingsPage(horizontalPadding: 0, verticalPadding: 0) {
                JinSettingsSection("Dimensions") {
                    JinSettingsTextFieldRow(
                        "Width × height", prompt: "2048x1152", text: $draftText, usesMonospacedFont: true
                    )
                        .onChange(of: draftText) { _, _ in
                            validationError = nil
                        }

                    Text(OpenAIImageModelSupport.sizeConstraintSummary(for: modelID, outputFormat: outputFormat))
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
        } actions: {
            Button("Cancel") {
                onCancel()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

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
            .keyboardShortcut(.defaultAction)
        }
        .frame(width: 520, height: 360)
    }
}
