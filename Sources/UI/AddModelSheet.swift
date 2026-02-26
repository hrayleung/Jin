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
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: JinSpacing.large) {
                        headerSection
                        identitySection
                        settingsSection
                    }
                    .padding(JinSpacing.xLarge)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background {
                LinearGradient(
                    colors: [
                        JinSemanticColor.detailSurface,
                        JinSemanticColor.surface.opacity(0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .navigationTitle("Add Model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addModel() }
                        .disabled(!canAddModel)
                }
            }
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
        .frame(minWidth: 560, minHeight: 360)
    }

    private var trimmedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedModelID: String {
        modelID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedModelName: String {
        trimmedNickname.isEmpty ? trimmedModelID : trimmedNickname
    }

    private var canAddModel: Bool {
        !trimmedModelID.isEmpty
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Text("Create a custom model entry")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Nickname is optional. Model ID should exactly match the provider identifier.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.large) {
            Text("Identity")
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: JinSpacing.medium) {
                fieldBlock(
                    title: "Nickname",
                    prompt: "Optional display name",
                    helperText: "Leave empty to use Model ID as the display name.",
                    text: $nickname,
                    monospaced: false
                )

                fieldBlock(
                    title: "Model ID",
                    prompt: "Required (for example: gpt-5.2-codex)",
                    helperText: "Used for API calls and capability inference.",
                    text: $modelID,
                    monospaced: true
                )
            }
        }
        .padding(JinSpacing.large)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            HStack(spacing: JinSpacing.small) {
                Label("Advanced Overrides", systemImage: "slider.horizontal.3")
                    .font(.headline)
                    .foregroundStyle(.primary)

                if customOverrides != nil {
                    Text("Configured")
                        .jinTagStyle(foreground: .accentColor)
                }
            }

            Text("Fine-tune capabilities, token limits, and reasoning behavior for this model.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: openModelSettings) {
                HStack(spacing: JinSpacing.small) {
                    Image(systemName: customOverrides == nil ? "gearshape" : "slider.horizontal.3")
                        .foregroundStyle(canAddModel ? Color.accentColor : Color.secondary)
                    Text(customOverrides == nil ? "Configure Model Settings" : "Edit Model Settings")
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, JinSpacing.medium)
                .padding(.vertical, JinSpacing.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .background {
                RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                    .fill(canAddModel ? JinSemanticColor.accentSurface : JinSemanticColor.subtleSurface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                    .stroke(
                        canAddModel ? Color.accentColor.opacity(0.32) : JinSemanticColor.separator.opacity(0.5),
                        lineWidth: JinStrokeWidth.hairline
                    )
            }
            .disabled(!canAddModel)

            if !canAddModel {
                Label("Enter Model ID first to configure settings.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(JinSpacing.large)
        .jinSurface(.subtleStrong, cornerRadius: JinRadius.large)
    }

    private func fieldBlock(
        title: String,
        prompt: String,
        helperText: String,
        text: Binding<String>,
        monospaced: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)

            TextField("", text: text, prompt: Text(prompt))
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .textFieldStyle(.plain)
                .padding(.horizontal, JinSpacing.medium)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                        .fill(JinSemanticColor.textSurface)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                        .stroke(JinSemanticColor.separator.opacity(0.55), lineWidth: JinStrokeWidth.hairline)
                }
                .onSubmit {
                    if canAddModel {
                        addModel()
                    }
                }

            Text(helperText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
        ModelCatalog.modelInfo(for: id, provider: providerType ?? .openaiCompatible, name: name)
    }
}