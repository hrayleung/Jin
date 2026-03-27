import SwiftUI
import AppKit

struct ChatSettingsView: View {
    @EnvironmentObject private var responseCompletionNotifier: ResponseCompletionNotifier
    @AppStorage(AppPreferenceKeys.sendWithCommandEnter) private var sendWithCommandEnter = false
    @AppStorage(AppPreferenceKeys.notifyOnBackgroundResponseCompletion) private var notifyOnBackgroundResponseCompletion = false
    @AppStorage(AppPreferenceKeys.networkDebugLoggingEnabled) private var networkDebugLoggingEnabled = false
    @AppStorage(AppPreferenceKeys.smartLongChatMemoryMode) private var smartLongChatMemoryMode = true

    var body: some View {
        Form {
            Section("Send Behavior") {
                Toggle("Use \u{2318}Return to send", isOn: $sendWithCommandEnter)
                Toggle("Smart Long Chat Memory Mode", isOn: $smartLongChatMemoryMode)
                Text("Keeps recent replies fully rendered while folding older heavy assistant messages to reduce RAM.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Enable Network Trace", isOn: $networkDebugLoggingEnabled)
                Text("JSON logs in time folders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
            } header: {
                Text("Network Trace")
            }

            Section("Notifications") {
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
                    Text("Notifications are disabled for Jin in System Settings > Notifications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
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
