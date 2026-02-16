import SwiftUI
import UserNotifications

struct ChatSettingsView: View {
    @EnvironmentObject private var responseCompletionNotifier: ResponseCompletionNotifier
    @AppStorage(AppPreferenceKeys.sendWithCommandEnter) private var sendWithCommandEnter = false
    @AppStorage(AppPreferenceKeys.notifyOnBackgroundResponseCompletion) private var notifyOnBackgroundResponseCompletion = false

    var body: some View {
        Form {
            Section("Send Behavior") {
                Toggle("Use \u{2318}Return to send", isOn: $sendWithCommandEnter)

                Text(sendBehaviorDescription)
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

                if let deliveryError = responseCompletionNotifier.lastDeliveryErrorMessage,
                   !deliveryError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(deliveryError)
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
        }
    }

    private var sendBehaviorDescription: String {
        if sendWithCommandEnter {
            return "Press Return to insert a new line. Press \u{2318}\u{21A9} to send."
        }
        return "Press Return to send. Press Shift+Return to insert a new line."
    }

    private var notificationDescription: String {
        if notifyOnBackgroundResponseCompletion {
            return "Jin sends a system notification when the current reply finishes while Jin is not the active app."
        }
        return "Turn on to receive a system notification after a reply completes in the background."
    }
}
