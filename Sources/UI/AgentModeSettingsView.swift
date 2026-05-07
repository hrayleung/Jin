import SwiftUI

struct AgentModeSettingsView: View {
    @AppStorage(AppPreferenceKeys.agentModeEnabled) var agentModeEnabled = false
    @AppStorage(AppPreferenceKeys.agentModeWorkingDirectory) var storedWorkingDirectory = ""
    @AppStorage(AppPreferenceKeys.agentModeAllowedCommandPrefixesJSON) var allowedPrefixesJSON = "[]"
    @AppStorage(AppPreferenceKeys.agentModeDefaultSafePrefixesJSON) var safePrefixesJSON = ""
    @AppStorage(AppPreferenceKeys.agentModeCommandTimeoutSeconds) var commandTimeoutSeconds = 120
    @AppStorage(AppPreferenceKeys.agentModeAutoApproveFileReads) var autoApproveFileReads = true

    @State var newPrefix = ""
    @State var newSafePrefix = ""
    @State var rtkStatus: RTKRuntimeStatus?
    @State var isRefreshingRTKStatus = false
    @State var workingDirectoryDraft = ""
    @AppStorage(AppPreferenceKeys.agentModeToolShell) var enableShell = true
    @AppStorage(AppPreferenceKeys.agentModeToolFileRead) var enableFileRead = true
    @AppStorage(AppPreferenceKeys.agentModeToolFileWrite) var enableFileWrite = true
    @AppStorage(AppPreferenceKeys.agentModeToolFileEdit) var enableFileEdit = true
    @AppStorage(AppPreferenceKeys.agentModeToolGlob) var enableGlob = true
    @AppStorage(AppPreferenceKeys.agentModeToolGrep) var enableGrep = true

    var allowedPrefixes: [String] {
        AppPreferences.decodeStringArrayJSON(allowedPrefixesJSON)
    }

    var safePrefixes: [String] {
        if safePrefixesJSON.isEmpty {
            return AgentCommandAllowlist.builtinDefaults
        }
        return AppPreferences.decodeStringArrayJSON(safePrefixesJSON)
    }

    var workingDirectoryValidation: AgentWorkingDirectorySupport.ValidationState {
        AgentWorkingDirectorySupport.validationState(for: workingDirectoryDraft)
    }

    var body: some View {
        JinSettingsPage {
            JinSettingsSection("Agent Mode") {
                JinSettingsToggleRow("Enable Agent Mode", isOn: $agentModeEnabled)
            }

            if agentModeEnabled {
                workingDirectorySection

                toolTogglesSection

                rtkSection

                safePrefixesSection

                allowedPrefixesSection

                safetySection

                detailsSection
            }
        }
        .navigationTitle("Agent Mode")
        .onAppear {
            syncWorkingDirectoryDraft()
        }
        .onChange(of: storedWorkingDirectory) { _, _ in
            syncWorkingDirectoryDraft()
        }
        .task(id: agentModeEnabled) {
            guard agentModeEnabled else { return }
            await refreshRTKStatus()
        }
    }
}
