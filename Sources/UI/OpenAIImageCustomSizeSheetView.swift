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

        let initialText: String
        if let currentSize, currentSize.isAuto == false {
            initialText = currentSize.displayName
        } else {
            initialText = ""
        }
        _draftText = State(initialValue: initialText)
    }

    private var trimmedDraft: String {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var parsedSize: OpenAIImageSize? {
        guard !trimmedDraft.isEmpty else { return nil }
        return OpenAIImageSize(rawValue: trimmedDraft)
    }

    private var currentValidationError: String? {
        guard let parsedSize else { return "Enter a size like `2048x1152`." }
        return OpenAIImageModelSupport.validate(size: parsedSize, for: modelID)
    }

    private var displayedValidationError: String? {
        if let validationError {
            return validationError
        }
        guard !trimmedDraft.isEmpty else { return nil }
        return currentValidationError
    }

    private var canSubmit: Bool {
        !trimmedDraft.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Custom Size") {
                    TextField("2048x1152", text: $draftText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
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
                        Text(validationError)
                            .foregroundStyle(.red)
                            .font(.caption)
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
                            validationError = "Enter a size like `2048x1152`."
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
