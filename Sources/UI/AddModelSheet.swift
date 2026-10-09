import SwiftUI

// MARK: - OpenRouter Usage Types

enum OpenRouterUsageStatus: Equatable {
    case idle
    case loading
    case observed
    case failure(String)
}

struct OpenRouterKeyUsage: Equatable {
    let used: Double
    let remaining: Double?

    func remainingText(formatter: (Double) -> String) -> String {
        guard let remaining else { return "Unavailable" }
        return formatter(remaining)
    }
}

struct OpenRouterKeyResponse: Decodable {
    let data: OpenRouterKeyData
}

struct OpenRouterKeyData: Decodable {
    let usage: Double?
    let limit: Double?
    let limitRemaining: Double?
}

struct OpenRouterCreditsResponse: Decodable {
    let data: OpenRouterCreditsData
}

struct OpenRouterCreditsData: Decodable {
    let totalCredits: Double?
    let totalUsage: Double?
}

// MARK: - Add Model Sheet

struct AddModelSheet: View {
    @Environment(\.dismiss) private var dismiss

    let providerType: ProviderType?
    let onAdd: (ModelInfo) -> Void

    @State private var nickname = ""
    @State private var modelID = ""
    @State private var customOverrides: ModelOverrides?
    @State private var editingModel: ModelInfo?

    var body: some View {
        JinSheet("Add Model") {
            JinSettingsPage(horizontalPadding: 0, verticalPadding: 0) {
                JinSettingsSection("Model") {
                    JinSettingsTextFieldRow(
                        providerType == .modal ? "Model ID or URL" : "Model ID",
                        prompt: providerType == .modal ? "Model ID or endpoint URL" : "Exact provider model ID",
                        supportingText: "Use the model ID supplied by your provider.",
                        text: $modelID,
                        usesMonospacedFont: true
                    )
                    JinSettingsTextFieldRow("Display name", prompt: "Optional", text: $nickname)
                }
                JinSettingsSection("Capabilities") {
                    Button(
                        customOverrides == nil ? "Configure Model Settings…" : "Edit Model Settings…",
                        action: openModelSettings
                    )
                        .disabled(!canAddModel)
                    Text(
                        canAddModel
                            ? "Review token limits, supported inputs, and reasoning options."
                            : "Enter a model ID to configure its capabilities."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        } actions: {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button("Add") { addModel() }
                .disabled(!canAddModel)
                .keyboardShortcut(.defaultAction)
        }
        .sheet(item: $editingModel) { model in
            ModelSettingsSheet(
                model: model,
                providerType: providerType,
                onSave: { updated in
                    customOverrides = updated.overrides
                }
            )
        }
        .frame(width: 560, height: 440)
    }

    private var trimmedNickname: String {
        AddModelSheetSupport.normalizedNickname(nickname)
    }

    private var trimmedModelID: String {
        AddModelSheetSupport.normalizedModelID(modelID, providerType: providerType)
    }

    private var resolvedModelName: String {
        AddModelSheetSupport.resolvedModelName(
            nickname: nickname,
            modelID: modelID,
            providerType: providerType
        )
    }

    private var canAddModel: Bool {
        AddModelSheetSupport.canAddModel(modelID: modelID, providerType: providerType)
    }

    private func openModelSettings() {
        guard canAddModel else { return }
        var draft = makeModelInfo(id: trimmedModelID, name: resolvedModelName)
        draft.overrides = customOverrides
        editingModel = draft
    }

    private func addModel() {
        guard canAddModel else { return }
        var model = makeModelInfo(id: trimmedModelID, name: resolvedModelName)
        model.overrides = customOverrides
        onAdd(model)
        dismiss()
    }

    private func makeModelInfo(id: String, name: String) -> ModelInfo {
        let info = ModelCatalog.modelInfo(for: id, provider: providerType ?? .openaiCompatible, name: name)
        guard providerType == .modal else { return info }
        return ModalEndpointSupport.applyEndpointMetadataIfNeeded(to: info)
    }
}
