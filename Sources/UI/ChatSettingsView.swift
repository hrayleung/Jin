import SwiftUI

struct ChatSettingsView: View {
    @EnvironmentObject private var responseCompletionNotifier: ResponseCompletionNotifier
    @AppStorage(AppPreferenceKeys.sendWithCommandEnter) private var sendWithCommandEnter = false
    @AppStorage(AppPreferenceKeys.notifyOnBackgroundResponseCompletion) private var notifyOnBackgroundResponseCompletion = false
    @AppStorage(AppPreferenceKeys.thinkingBlockDisplayMode) private var thinkingDisplayModeRaw = ThinkingBlockDisplayMode.expanded.rawValue

    private var thinkingDisplayMode: Binding<ThinkingBlockDisplayMode> {
        Binding(
            get: { ThinkingBlockDisplayMode(rawValue: thinkingDisplayModeRaw) ?? .expanded },
            set: { thinkingDisplayModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Send Behavior") {
                Toggle("Use \u{2318}Return to send", isOn: $sendWithCommandEnter)

                Text(sendBehaviorDescription)
                    .jinInfoCallout()
            }

            Section("Thinking Blocks") {
                Picker("Display Mode", selection: thinkingDisplayMode) {
                    ForEach(ThinkingBlockDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Text(currentThinkingModeDescription)
                    .jinInfoCallout()
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

                Text(notificationDescription)
                    .jinInfoCallout()

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

    private var sendBehaviorDescription: String {
        if sendWithCommandEnter {
            return "Press Return to insert a new line. Press \u{2318}\u{21A9} to send."
        }
        return "Press Return to send. Press Shift+Return to insert a new line."
    }

    private var currentThinkingModeDescription: String {
        let mode = ThinkingBlockDisplayMode(rawValue: thinkingDisplayModeRaw) ?? .expanded
        return mode.description
    }

    private var notificationDescription: String {
        if notifyOnBackgroundResponseCompletion {
            return "Jin sends a system notification when the current reply finishes while Jin is not the active app."
        }
        return "Turn on to receive a system notification after a reply completes in the background."
    }
}
