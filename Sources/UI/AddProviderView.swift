import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct AddProviderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ProviderType.openai.displayName
    @State private var providerType: ProviderType = .openai
    @State private var iconID: String? = LobeProviderIconCatalog.defaultIconID(for: .openai)
    @State private var baseURL = ProviderType.openai.defaultBaseURL ?? ""
    @State private var apiKey = ""
    @State private var serviceAccountJSON = ""

    @State private var isKeyVisible = false
    @State private var isSaving = false
    @State private var saveError: String?

    private var prefersExpandedCredentialEditor: Bool {
        providerType == .vertexai
    }

    var body: some View {
        NavigationStack {
            JinSettingsPage(
                maxWidth: prefersExpandedCredentialEditor ? 760 : 560,
                horizontalPadding: 20,
                verticalPadding: 20
            ) {
                JinSettingsSection("Provider") {
                    JinSettingsControlRow("Name", supportingText: "Required.") {
                        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                            TextField("Provider name", text: $name, prompt: Text("e.g., \(providerType.displayName)"))
                                .textFieldStyle(.roundedBorder)

                            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Name is required.")
                                    .jinInlineErrorText()
                            }
                        }
                    }

                    JinSettingsControlRow("Icon") {
                        ProviderIconPickerField(
                            selectedIconID: $iconID,
                            defaultIconID: LobeProviderIconCatalog.defaultIconID(for: providerType)
                        )
                    }

                    JinSettingsPickerRow("Type", selection: $providerType) {
                        ForEach(ProviderType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .onChange(of: providerType) { oldValue, newValue in
                        let values = ProviderFormSupport.updatedDraftValues(
                            oldType: oldValue,
                            newType: newValue,
                            name: name,
                            baseURL: baseURL,
                            iconID: iconID
                        )
                        name = values.name
                        baseURL = values.baseURL
                        iconID = values.iconID
                    }

                    if providerType != .vertexai {
                        JinSettingsTextFieldRow(
                            "API Base URL",
                            supportingText: "Default endpoint is pre-filled.",
                            text: $baseURL,
                            usesMonospacedFont: true
                        )
                        .help("Default endpoint is pre-filled.")
                    }

                    if let providerSetupCallout {
                        Text(providerSetupCallout)
                            .jinInfoCallout()
                    }

                    if let providerDetailsText {
                        JinDetailsDisclosure(title: "Provider Details") {
                            Text(providerDetailsText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                JinSettingsSection("Credentials") {
                    switch ProviderFormSupport.credentialKind(for: providerType) {
                    case .optionalAPIKey:
                        JinSettingsSecureFieldRow(
                            "API Key",
                            fieldTitle: "API Key (Optional)",
                            supportingText: "Optional. Leave blank to use ChatGPT account login in provider settings.",
                            text: $apiKey,
                            isRevealed: $isKeyVisible,
                            revealHelp: "Show API key",
                            concealHelp: "Hide API key"
                        )
                    case .apiKey:
                        JinSettingsSecureFieldRow(
                            ProviderFormSupport.apiKeyFieldTitle(for: providerType),
                            text: $apiKey,
                            isRevealed: $isKeyVisible,
                            revealHelp: ProviderFormSupport.apiKeyRevealHelp(for: providerType),
                            concealHelp: ProviderFormSupport.apiKeyConcealHelp(for: providerType)
                        )
                    case .serviceAccountJSON:
                        JinSettingsBlockRow(
                            "Service Account JSON",
                            supportingText: "Paste the full service account JSON document."
                        ) {
                            JinSettingsTextEditor(
                                text: $serviceAccountJSON,
                                placeholder: "Paste service account JSON here…",
                                minHeight: 320,
                                placeholderLeadingPadding: 4
                            )
                        }
                    }

                    if let saveError {
                        Text(saveError)
                            .jinInlineErrorText()
                    }
                }
            }
            .navigationTitle("Add Provider")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addProvider() }
                        .disabled(isAddDisabled)
                }
            }
            .frame(
                width: prefersExpandedCredentialEditor ? 740 : 500,
                height: prefersExpandedCredentialEditor ? 660 : 400
            )
        }
        #if os(macOS)
        .background(MovableWindowHelper())
        #endif
    }

    private func addProvider() {
        isSaving = true
        saveError = nil

        Task {
            do {
                let providerID = UUID().uuidString
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedServiceAccountJSON = serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines)

                if providerType == .vertexai {
                    _ = try JSONDecoder().decode(ServiceAccountCredentials.self, from: Data(trimmedServiceAccountJSON.utf8))
                }

                let isVertexAI = providerType == .vertexai
                let resolvedAPIKey: String? = isVertexAI ? nil : ProviderFormSupport.normalizedOptionalString(trimmedAPIKey)
                let resolvedBaseURL = ProviderFormSupport.normalizedBaseURL(trimmedBaseURL, providerType: providerType)

                let config = ProviderConfig(
                    id: providerID,
                    name: trimmedName,
                    type: providerType,
                    iconID: ProviderFormSupport.normalizedIconID(iconID),
                    apiKey: resolvedAPIKey,
                    serviceAccountJSON: isVertexAI ? trimmedServiceAccountJSON : nil,
                    baseURL: resolvedBaseURL
                )

                let entity = try ProviderConfigEntity.fromDomain(config)

                await MainActor.run {
                    modelContext.insert(entity)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    saveError = error.localizedDescription
                }
            }
        }
    }

    private var providerSetupCallout: String? {
        ProviderFormSupport.providerSetupCallout(for: providerType)
    }

    private var providerDetailsText: String? {
        ProviderFormSupport.providerDetailsText(for: providerType)
    }

    private var isAddDisabled: Bool {
        ProviderFormSupport.isAddDisabled(
            providerType: providerType,
            name: name,
            apiKey: apiKey,
            serviceAccountJSON: serviceAccountJSON,
            isSaving: isSaving
        )
    }
}
