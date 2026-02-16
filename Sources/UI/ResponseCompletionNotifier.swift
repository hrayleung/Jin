import Foundation
import UserNotifications
#if os(macOS)
import AppKit
#endif

@MainActor
final class ResponseCompletionNotifier: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var lastDeliveryErrorMessage: String?

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults

    init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard
    ) {
        self.center = center
        self.defaults = defaults
        Task {
            await refreshAuthorizationStatus()
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await notificationSettings()
        authorizationStatus = settings.authorizationStatus

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            lastDeliveryErrorMessage = nil
            return true
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            await refreshAuthorizationStatus()
            if !granted {
                lastDeliveryErrorMessage = "Notification permission was not granted."
            } else {
                lastDeliveryErrorMessage = nil
            }
            return granted
        case .denied:
            lastDeliveryErrorMessage = "Notifications are disabled for Jin in System Settings."
            return false
        @unknown default:
            lastDeliveryErrorMessage = "Unable to determine notification permission state."
            return false
        }
    }

    func prepareAuthorizationIfNeededWhileActive() {
        Task {
            guard defaults.bool(forKey: AppPreferenceKeys.notifyOnBackgroundResponseCompletion) else {
                return
            }
            #if os(macOS)
            guard NSApplication.shared.isActive else { return }
            #endif
            _ = await requestAuthorizationIfNeeded()
        }
    }

    func notifyCompletionIfNeeded(
        conversationID: UUID,
        conversationTitle: String,
        replyPreview: String?
    ) {
        Task {
            guard defaults.bool(forKey: AppPreferenceKeys.notifyOnBackgroundResponseCompletion) else {
                return
            }
            #if os(macOS)
            guard !NSApplication.shared.isActive else { return }
            #endif

            let settings = await notificationSettings()
            authorizationStatus = settings.authorizationStatus
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                if settings.authorizationStatus == .notDetermined {
                    lastDeliveryErrorMessage = "Open Jin and allow notifications first."
                } else {
                    lastDeliveryErrorMessage = "Notifications are disabled for Jin in System Settings."
                }
                return
            }

            guard settings.alertSetting == .enabled || settings.notificationCenterSetting == .enabled else {
                lastDeliveryErrorMessage = "Notifications are authorized but disabled for banners and Notification Center."
                return
            }

            let content = UNMutableNotificationContent()
            let trimmedTitle = conversationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            content.title = trimmedTitle.isEmpty ? "Jin" : trimmedTitle
            content.subtitle = "Reply completed"

            let trimmedPreview = (replyPreview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            content.body = trimmedPreview.isEmpty ? "Your assistant reply is ready." : trimmedPreview
            content.sound = .default
            content.threadIdentifier = "jin.conversation.\(conversationID.uuidString)"
            content.userInfo = ["conversationID": conversationID.uuidString]

            let request = UNNotificationRequest(
                identifier: "jin.reply.\(conversationID.uuidString).\(UUID().uuidString)",
                content: content,
                trigger: nil
            )

            do {
                try await addNotificationRequest(request)
                await MainActor.run {
                    lastDeliveryErrorMessage = nil
                }
            } catch {
                await MainActor.run {
                    lastDeliveryErrorMessage = "Notification delivery failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private func addNotificationRequest(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
