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
            JinSettingsSection("Send Behavior") {
                Toggle("Use \u{2318}Return to send", isOn: $sendWithCommandEnter)
            }

            JinSettingsSection("Network Trace") {
                Toggle("Enable Network Trace", isOn: $networkDebugLoggingEnabled)
                JinSettingsStatusText(text: "JSON logs in time folders.")

                HStack(spacing: JinSpacing.small) {
                    Button("Open Trace Folder") {
                        let folder = NetworkDebugLogger.logRootDirectoryURL
                        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(folder)
                    }
                    .disabled(!networkDebugLoggingEnabled)

                    Button("Clear Traces") {
                        Task {
                            try? await NetworkDebugLogger.shared.clearLogs()
                        }
                    }
                }
            }

            JinSettingsSection("Chat Diagnostics") {
                Toggle("Enable Chat Diagnostics", isOn: $chatDiagnosticLoggingEnabled)
                JinSettingsStatusText(text: "Lightweight NDJSON timing logs for the chat send/stream pipeline.")

                HStack(spacing: JinSpacing.small) {
                    Button("Open Diagnostic Folder") {
                        let folder = ChatDiagnosticLogger.logRootDirectoryURL
                        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(folder)
                    }
                    .disabled(!chatDiagnosticLoggingEnabled)

                    Button("Clear Diagnostics") {
                        Task {
                            try? await ChatDiagnosticLogger.shared.clearLogs()
                        }
                    }
                }
            }

            JinSettingsSection("Notifications") {
                Toggle("Notify when replies finish in background", isOn: $notifyOnBackgroundResponseCompletion)
                    .onChange(of: notifyOnBackgroundResponseCompletion) { _, enabled in
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

                if responseCompletionNotifier.authorizationStatus == .denied {
                    JinSettingsStatusText(text: "Notifications are disabled for Jin in System Settings > Notifications.")
                }
            }
        }
        .navigationTitle("Chat")
        .task {
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
}
