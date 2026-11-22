import SwiftUI
import AppKit

struct ChatSettingsView: View {
    @EnvironmentObject private var responseCompletionNotifier: ResponseCompletionNotifier
    @AppStorage(AppPreferenceKeys.sendWithCommandEnter) private var sendWithCommandEnter = false
    @AppStorage(AppPreferenceKeys.notifyOnBackgroundResponseCompletion) private var notifyOnBackgroundResponseCompletion = false
    @AppStorage(AppPreferenceKeys.networkDebugLoggingEnabled) private var networkDebugLoggingEnabled = false
    @AppStorage(AppPreferenceKeys.chatDiagnosticLoggingEnabled) private var chatDiagnosticLoggingEnabled = false

    var body: some View {
        JinSettingsPage(title: "Chat") {
            sendBehaviorSection
            notificationsSection
            networkTraceSection
            chatDiagnosticsSection
        }
        .task {
            await refreshNotificationAuthorization()
        }
    }

    private var sendBehaviorSection: some View {
        JinSettingsSection("Sending") {
            JinSettingsToggleRow(
                "Send with \u{2318}Return",
                supportingText: "Return starts a new line instead of sending.",
                isOn: $sendWithCommandEnter
            )
        }
    }

    private var notificationsSection: some View {
        JinSettingsSection("Notifications") {
            JinSettingsToggleRow(
                "Notify when a reply finishes in the background",
                supportingText: responseCompletionNotifier.authorizationStatus == .denied
                    ? "Notifications for Jin are turned off in System Settings."
                    : nil,
                isOn: $notifyOnBackgroundResponseCompletion
            )
            .onChange(of: notifyOnBackgroundResponseCompletion) { _, enabled in
                handleNotificationToggle(enabled: enabled)
            }
        }
    }

    private var networkTraceSection: some View {
        JinSettingsSection("Network Trace") {
            JinSettingsToggleRow(
                "Record network traces",
                supportingText: "Saves request and response metadata as JSON. Bodies, API keys, cookies, and sensitive URL parameters are left out.",
                isOn: $networkDebugLoggingEnabled
            )

            ChatSettingsLogActionsRow(
                title: "Trace files",
                isOpenDisabled: !networkDebugLoggingEnabled,
                onOpen: openNetworkTraceFolder,
                onClear: clearNetworkTraces
            )
        }
    }

    private var chatDiagnosticsSection: some View {
        JinSettingsSection("Chat Diagnostics") {
            JinSettingsToggleRow(
                "Record chat diagnostics",
                supportingText: "Saves timing logs for sending and streaming a reply.",
                isOn: $chatDiagnosticLoggingEnabled
            )

            ChatSettingsLogActionsRow(
                title: "Diagnostic files",
                isOpenDisabled: !chatDiagnosticLoggingEnabled,
                onOpen: openChatDiagnosticFolder,
                onClear: clearChatDiagnostics
            )
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
    let title: String
    let isOpenDisabled: Bool
    let onOpen: () -> Void
    let onClear: () -> Void

    var body: some View {
        JinSettingsControlRow(title) {
            HStack(spacing: JinSpacing.small) {
                Button("Show in Finder", action: onOpen)
                    .disabled(isOpenDisabled)

                Button("Clear", action: onClear)
            }
            .controlSize(.small)
        }
    }
}
