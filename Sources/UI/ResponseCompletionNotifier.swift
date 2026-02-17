import Foundation
import UserNotifications
#if os(macOS)
import AppKit
#endif

@MainActor
final class ResponseCompletionNotifier: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let delegateProxy = NotificationDelegateProxy()

    init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard
    ) {
        self.center = center
        self.defaults = defaults
        self.center.delegate = delegateProxy
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
            return true
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            await refreshAuthorizationStatus()
            return granted
        case .denied:
            return false
        @unknown default:
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
                return
            }

            guard notificationsPresentationAllowed(settings) else {
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
            if #available(macOS 12.0, *) {
                content.interruptionLevel = .active
            }

            let request = UNNotificationRequest(
                identifier: "jin.reply.\(conversationID.uuidString).\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )

            try? await addNotificationRequest(request)
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

    private func notificationsPresentationAllowed(_ settings: UNNotificationSettings) -> Bool {
        let alertAllowed = settings.alertSetting == .enabled || settings.alertSetting == .notSupported
        let centerAllowed = settings.notificationCenterSetting == .enabled || settings.notificationCenterSetting == .notSupported
        return alertAllowed || centerAllowed
    }
}

private final class NotificationDelegateProxy: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }
}
