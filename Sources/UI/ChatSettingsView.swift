import SwiftUI
import AppKit

struct ChatSettingsView: View {
    @EnvironmentObject private var responseCompletionNotifier: ResponseCompletionNotifier
    @AppStorage(AppPreferenceKeys.sendWithCommandEnter) private var sendWithCommandEnter = false
    @AppStorage(AppPreferenceKeys.notifyOnBackgroundResponseCompletion) private var notifyOnBackgroundResponseCompletion = false
    @AppStorage(AppPreferenceKeys.networkDebugLoggingEnabled) private var networkDebugLoggingEnabled = false
    @AppStorage(AppPreferenceKeys.chatDiagnosticLoggingEnabled) private var chatDiagnosticLoggingEnabled = false

    var body: some View {
        JinSettingsPage {
            sendBehaviorSection
            networkTraceSection
            chatDiagnosticsSection
            notificationsSection
        }
        .navigationTitle("Chat")
        .task {
            await refreshNotificationAuthorization()
        }
    }

    private var sendBehaviorSection: some View {
        JinSettingsSection("Send Behavior") {
            JinSettingsToggleRow("Use \u{2318}Return to send", isOn: $sendWithCommandEnter)
        }
    }

    private var networkTraceSection: some View {
        JinSettingsSection("Network Trace") {
            JinSettingsToggleRow("Enable Network Trace", isOn: $networkDebugLoggingEnabled)
            JinSettingsStatusText(text: "JSON logs in time folders.")

            ChatSettingsLogActionsRow(
                openTitle: "Open Trace Folder",
                clearTitle: "Clear Traces",
                isOpenDisabled: !networkDebugLoggingEnabled,
                onOpen: openNetworkTraceFolder,
                onClear: clearNetworkTraces
            )
        }
    }

    private var chatDiagnosticsSection: some View {
        JinSettingsSection("Chat Diagnostics") {
            JinSettingsToggleRow("Enable Chat Diagnostics", isOn: $chatDiagnosticLoggingEnabled)
            JinSettingsStatusText(text: "Lightweight NDJSON timing logs for the chat send/stream pipeline.")

            ChatSettingsLogActionsRow(
                openTitle: "Open Diagnostic Folder",
                clearTitle: "Clear Diagnostics",
                isOpenDisabled: !chatDiagnosticLoggingEnabled,
                onOpen: openChatDiagnosticFolder,
                onClear: clearChatDiagnostics
            )
        }
    }

    private var notificationsSection: some View {
        JinSettingsSection("Notifications") {
            JinSettingsToggleRow("Notify when replies finish in background", isOn: $notifyOnBackgroundResponseCompletion)
                .onChange(of: notifyOnBackgroundResponseCompletion) { _, enabled in
                    handleNotificationToggle(enabled: enabled)
                }

            if responseCompletionNotifier.authorizationStatus == .denied {
                JinSettingsStatusText(text: "Notifications are disabled for Jin in System Settings > Notifications.")
            }
        }
    }

    private func openNetworkTraceFolder() {
        openFolder(NetworkDebugLogger.logRootDirectoryURL)
    }

    private func clearNetworkTraces() {
        Task {
            try? await NetworkDebugLogger.shared.clearLogs()
        }
    }

    private func openChatDiagnosticFolder() {
        openFolder(ChatDiagnosticLogger.logRootDirectoryURL)
    }

    private func clearChatDiagnostics() {
        Task {
            try? await ChatDiagnosticLogger.shared.clearLogs()
        }
    }

    private func openFolder(_ folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    private func handleNotificationToggle(enabled: Bool) {
        guard enabled else { return }
        Task {
            let granted = await responseCompletionNotifier.requestAuthorizationIfNeeded()
            if !granted {
                await MainActor.run {
                    notifyOnBackgroundResponseCompletion = false
                }
            }
        }
    }

    private func refreshNotificationAuthorization() async {
        await responseCompletionNotifier.refreshAuthorizationStatus()
        guard notifyOnBackgroundResponseCompletion,
              responseCompletionNotifier.authorizationStatus == .notDetermined else {
            return
        }
        let granted = await responseCompletionNotifier.requestAuthorizationIfNeeded()
        if !granted {
            notifyOnBackgroundResponseCompletion = false
        }
    }
}

private struct ChatSettingsLogActionsRow: View {
    let openTitle: String
    let clearTitle: String
    let isOpenDisabled: Bool
    let onOpen: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            Button(openTitle, action: onOpen)
                .disabled(isOpenDisabled)

            Button(clearTitle, action: onClear)
        }
    }
}
