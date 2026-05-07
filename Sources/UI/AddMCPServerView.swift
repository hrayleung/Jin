import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct AddMCPServerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

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

    @State private var runToolsAutomatically = true
    @State private var isEnabled = true

    @State private var preset: AddMCPServerPreset = .custom
    @State private var isImportSectionExpanded = false
    @State private var importJSON = ""
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            JinSettingsPage(maxWidth: 720, horizontalPadding: 20, verticalPadding: 20) {
                AddMCPServerQuickSetupSection(
                    preset: $preset,
                    isImportSectionExpanded: $isImportSectionExpanded,
                    importJSON: $importJSON,
                    importError: importError,
                    onImport: importFromJSON
                )
                .onChange(of: preset) { _, newValue in
                    applyPreset(newValue)
                }

                AddMCPServerIdentitySection(
                    id: $id,
                    name: $name,
                    iconID: $iconID,
                    transportKind: $transportKind,
                    isEnabled: $isEnabled,
                    runToolsAutomatically: $runToolsAutomatically
                )

                if transportKind == .stdio {
                    MCPServerStdioTransportSections(
                        command: $command,
                        argsText: $args,
                        envPairs: $envPairs,
                        argsError: nil,
                        showsNodeIsolationNote: shouldShowNodeIsolationNote,
                        showsFirecrawlAPIKeyWarning: false
                    )
                } else {
                    MCPServerHTTPTransportSections(
                        endpoint: $endpoint,
                        httpStreaming: $httpStreaming,
                        endpointError: nil,
                        httpAuthKind: $httpAuthKind,
                        bearerToken: $bearerToken,
                        authHeaderName: $authHeaderName,
                        authHeaderValue: $authHeaderValue,
                        headerPairs: $headerPairs,
                        isBearerTokenVisible: $isBearerTokenVisible,
                        isHeaderValueVisible: $isHeaderValueVisible,
                        authenticationError: httpAuthenticationValidationError
                    )
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                AddMCPServerActionBar(
                    isAddDisabled: isAddDisabled,
                    onCancel: { dismiss() },
                    onAdd: addServer
                )
            }
            .navigationTitle("Add MCP Server")
            .onExitCommand { dismiss() }
            .frame(
                minWidth: 620,
                idealWidth: 680,
                maxWidth: 760,
                minHeight: 540,
                idealHeight: 680,
                maxHeight: 760
            )
        }
        #if os(macOS)
        .background(MovableWindowHelper())
        #endif
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

    private var shouldShowNodeIsolationNote: Bool {
        MCPServerFormSupport.shouldShowNodeIsolationNote(command: command)
    }

    private func applyPreset(_ preset: AddMCPServerPreset) {
        importError = nil
        guard preset != .custom else { return }
        applyPresetDraft(AddMCPServerPresetSupport.applyingPreset(preset, to: presetDraft))
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
        httpAuthKind = fields.kind
        bearerToken = fields.bearerToken
        authHeaderName = fields.headerName
        authHeaderValue = fields.headerValue
    }

    private var presetDraft: AddMCPServerPresetSupport.Draft {
        AddMCPServerPresetSupport.Draft(
            id: id,
            name: name,
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
        transportKind = draft.transportKind
        command = draft.command
        args = draft.args
        envPairs = draft.envPairs
        endpoint = draft.endpoint
        headerPairs = draft.headerPairs
        applyHTTPAuthentication(draft.httpAuthentication)
    }

}
