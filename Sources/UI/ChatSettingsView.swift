import SwiftUI
import AppKit

struct ChatSettingsView: View {
    @EnvironmentObject private var responseCompletionNotifier: ResponseCompletionNotifier
    @AppStorage(AppPreferenceKeys.sendWithCommandEnter) private var sendWithCommandEnter = false
    @AppStorage(AppPreferenceKeys.notifyOnBackgroundResponseCompletion) private var notifyOnBackgroundResponseCompletion = false
    @AppStorage(AppPreferenceKeys.thinkingBlockDisplayMode) private var thinkingDisplayModeRaw = ThinkingBlockDisplayMode.expanded.rawValue
    @AppStorage(AppPreferenceKeys.codexToolDisplayMode) private var codexToolDisplayModeRaw = CodexToolDisplayMode.expanded.rawValue
    @AppStorage(AppPreferenceKeys.networkDebugLoggingEnabled) private var networkDebugLoggingEnabled = false

    private var thinkingDisplayMode: Binding<ThinkingBlockDisplayMode> {
        Binding(
            get: { ThinkingBlockDisplayMode(rawValue: thinkingDisplayModeRaw) ?? .expanded },
            set: { thinkingDisplayModeRaw = $0.rawValue }
        )
    }

    private var codexToolDisplayMode: Binding<CodexToolDisplayMode> {
        Binding(
            get: { CodexToolDisplayMode(rawValue: codexToolDisplayModeRaw) ?? .expanded },
            set: { codexToolDisplayModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Send Behavior") {
                Toggle("Use \u{2318}Return to send", isOn: $sendWithCommandEnter)
            }

            Section("Thinking Blocks") {
                Picker("Display Mode", selection: thinkingDisplayMode) {
                    ForEach(ThinkingBlockDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }

            Section("Codex Tool Activities") {
                Picker("Display Mode", selection: codexToolDisplayMode) {
                    ForEach(CodexToolDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
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
