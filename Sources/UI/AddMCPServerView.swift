import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct AddMCPServerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .catalog
    @State private var searchText = ""
    @State private var category: MCPServerCatalogCategory = .all

    @State private var id = ""
    @State private var name = ""
    @State private var iconID: String?
    @State private var transportKind: MCPTransportKind = .stdio

    @State private var command = ""
    @State private var args = ""
    @State private var envPairs: [EnvironmentVariablePair] = []

    @State private var endpoint = ""
    @State private var httpAuthKind: MCPHTTPAuthentication.FormKind = .none
    @State private var bearerToken = ""
    @State private var authHeaderName = "Authorization"
    @State private var authHeaderValue = ""
    @State private var headerPairs: [EnvironmentVariablePair] = []
    @State private var httpStreaming = true
    @State private var isBearerTokenVisible = false
    @State private var isHeaderValueVisible = false
    @State private var isCredentialVisible = false

    @State private var runToolsAutomatically = true
    @State private var isEnabled = true

    @State private var preset: AddMCPServerPreset = .custom
    @State private var isImportSectionExpanded = false
    @State private var importJSON = ""
    @State private var importError: String?

    private enum Step: Equatable {
        case catalog
        case configure
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    switch step {
                    case .catalog:
                        AddMCPServerCatalogSection(
                            searchText: $searchText,
                            category: $category,
                            items: filteredCatalogItems,
                            onSelect: selectPreset
                        )
                    case .configure:
                        AddMCPServerConfigureSection(
                            preset: preset,
                            catalogItem: MCPServerCatalog.item(for: preset),
                            id: $id,
                            name: $name,
                            iconID: $iconID,
                            transportKind: $transportKind,
                            isEnabled: $isEnabled,
                            runToolsAutomatically: $runToolsAutomatically,
                            credentialValue: credentialBinding,
                            isCredentialVisible: $isCredentialVisible,
                            command: $command,
                            args: $args,
                            envPairs: $envPairs,
                            endpoint: $endpoint,
                            httpAuthKind: $httpAuthKind,
                            bearerToken: $bearerToken,
                            authHeaderName: $authHeaderName,
                            authHeaderValue: $authHeaderValue,
                            headerPairs: $headerPairs,
                            httpStreaming: $httpStreaming,
                            isBearerTokenVisible: $isBearerTokenVisible,
                            isHeaderValueVisible: $isHeaderValueVisible,
                            importJSON: $importJSON,
                            importError: importError,
                            authenticationError: httpAuthenticationValidationError,
                            onImport: importFromJSON
                        )
                    }
                }
                .padding(JinSpacing.xLarge)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(JinSemanticColor.detailSurface)
            .navigationTitle(step == .catalog ? "Add MCP Server" : configureTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step == .configure {
                        Button("Back") { step = .catalog }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if step == .configure {
                        Button("Add", action: addServer)
                            .disabled(isAddDisabled)
                    }
                }
            }
            .onExitCommand { dismiss() }
            .frame(
                minWidth: 680,
                idealWidth: 740,
                maxWidth: 820,
                minHeight: 560,
                idealHeight: 700,
                maxHeight: 820
            )
        }
        #if os(macOS)
        .background(MovableWindowHelper())
        #endif
    }

    private var filteredCatalogItems: [MCPServerCatalogItem] {
        MCPServerCatalog.filtered(query: searchText, category: category)
    }

    private var configureTitle: String {
        MCPServerCatalog.item(for: preset)?.title ?? preset.rawValue
    }

    private var isAddDisabled: Bool {
        MCPServerFormSupport.isAddServerDisabled(
            name: name,
            transportKind: transportKind,
            command: command,
            parsedEndpoint: parsedEndpoint,
            parsedHTTPAuthentication: parsedHTTPAuthentication
        )
    }

    private var parsedEndpoint: URL? {
        MCPServerFormSupport.parsedEndpoint(endpoint)
    }

    private var credentialBinding: Binding<String> {
        Binding(
            get: {
                AddMCPServerPresetSupport.credentialValue(for: preset, draft: presetDraft)
            },
            set: { newValue in
                applyPresetDraft(
                    AddMCPServerPresetSupport.applyingCredential(newValue, for: preset, to: presetDraft)
                )
            }
        )
    }

    private func selectPreset(_ newPreset: AddMCPServerPreset) {
        importError = nil
        preset = newPreset
        applyPresetDraft(AddMCPServerPresetSupport.applyingPreset(newPreset, to: .blank))
        step = .configure
    }

    private func importFromJSON() {
        importError = nil

        do {
            let imported = try MCPServerImportParser.parse(json: importJSON)

            id = imported.id
            name = imported.name
            applyImportedTransport(imported.transport)
            isImportSectionExpanded = false
        } catch {
            importError = MCPServerImportErrorPresentation.message(for: error)
            isImportSectionExpanded = true
        }
    }

    private func applyImportedTransport(_ transport: MCPTransportConfig) {
        let draft = MCPServerTransportDraftSupport.draft(from: transport)
        transportKind = draft.transportKind
        command = draft.command
        args = draft.argsText
        envPairs = draft.envPairs
        endpoint = draft.endpoint
        applyHTTPAuthentication(draft.httpAuthentication)
        headerPairs = draft.headerPairs
        httpStreaming = draft.httpStreaming
    }

    private func addServer() {
        let transport: MCPTransportConfig
        do {
            transport = try MCPServerTransportDraftSupport.buildTransport(from: transportBuildRequest)
        } catch let error as MCPServerTransportDraftSupport.BuildError {
            importError = addServerMessage(for: error)
            return
        } catch {
            importError = error.localizedDescription
            return
        }

        let serverID = MCPServerFormSupport.normalizedServerID(id)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedIconID = MCPServerFormSupport.normalizedIconID(iconID)
        let transportData = (try? JSONEncoder().encode(transport)) ?? Data()

        let server = MCPServerConfigEntity(
            id: serverID,
            name: trimmedName,
            iconID: normalizedIconID,
            transportKindRaw: transport.kind.rawValue,
            transportData: transportData,
            lifecycleRaw: MCPLifecyclePolicy.persistent.rawValue,
            isEnabled: isEnabled,
            runToolsAutomatically: runToolsAutomatically,
            isLongRunning: true
        )
        do {
            try server.setTransport(transport)
        } catch {
            importError = "Failed to save transport config: \(error.localizedDescription)"
            return
        }

        modelContext.insert(server)
        try? modelContext.save()
        dismiss()
    }

    private var transportBuildRequest: MCPServerTransportDraftSupport.BuildRequest {
        MCPServerTransportDraftSupport.BuildRequest(
            transportKind: transportKind,
            command: command,
            argsText: args,
            envPairs: envPairs,
            endpoint: endpoint,
            httpAuthentication: parsedHTTPAuthentication,
            headerPairs: headerPairs,
            httpStreaming: httpStreaming
        )
    }

    private func addServerMessage(for error: MCPServerTransportDraftSupport.BuildError) -> String {
        switch error {
        case .invalidAuthentication:
            return httpAuthenticationValidationError ?? error.localizedDescription
        case .invalidArguments, .invalidEndpointURL:
            return error.localizedDescription
        }
    }

    private var httpAuthenticationValidationError: String? {
        MCPHTTPAuthentication.formValidationError(
            kind: httpAuthKind,
            bearerToken: bearerToken,
            headerName: authHeaderName,
            headerValue: authHeaderValue
        )
    }

    private var parsedHTTPAuthentication: MCPHTTPAuthentication? {
        MCPHTTPAuthentication.fromFormFields(
            kind: httpAuthKind,
            bearerToken: bearerToken,
            headerName: authHeaderName,
            headerValue: authHeaderValue
        )
    }

    private func applyHTTPAuthentication(_ authentication: MCPHTTPAuthentication) {
        let fields = authentication.formFields
        httpAuthKind = MCPHTTPAuthentication.FormKind.coerced(fields.kind, forEndpoint: endpoint)
        bearerToken = fields.bearerToken
        authHeaderName = fields.headerName
        authHeaderValue = fields.headerValue
    }

    private var presetDraft: AddMCPServerPresetSupport.Draft {
        AddMCPServerPresetSupport.Draft(
            id: id,
            name: name,
            iconID: iconID,
            transportKind: transportKind,
            command: command,
            args: args,
            envPairs: envPairs,
            endpoint: endpoint,
            headerPairs: headerPairs,
            httpAuthentication: parsedHTTPAuthentication ?? .none
        )
    }

    private func applyPresetDraft(_ draft: AddMCPServerPresetSupport.Draft) {
        id = draft.id
        name = draft.name
        iconID = draft.iconID
        transportKind = draft.transportKind
        command = draft.command
        args = draft.args
        envPairs = draft.envPairs
        endpoint = draft.endpoint
        headerPairs = draft.headerPairs
        applyHTTPAuthentication(draft.httpAuthentication)
    }
}
