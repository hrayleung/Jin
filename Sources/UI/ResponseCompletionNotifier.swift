import Foundation
import UserNotifications
#if os(macOS)
import AppKit
#endif

@MainActor
final class ResponseCompletionNotifier: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var lastDeliveryErrorMessage: String?
    @Published private(set) var diagnosticsSummary: String = "Notifications status unavailable."
    @Published private(set) var pendingRequestCount: Int = 0
    @Published private(set) var deliveredNotificationCount: Int = 0
    @Published private(set) var lastScheduledNotificationID: String?

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
            await refreshQueueDiagnostics()
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await notificationSettings()
        apply(settings: settings)
        await refreshQueueDiagnostics()
    }

    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await notificationSettings()
        apply(settings: settings)

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            lastDeliveryErrorMessage = nil
            await refreshQueueDiagnostics()
            return true
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            await refreshAuthorizationStatus()
            if !granted {
                lastDeliveryErrorMessage = "Notification permission was not granted."
            } else {
                lastDeliveryErrorMessage = nil
                await refreshQueueDiagnostics()
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

    func sendTestNotification() {
        Task {
            guard await requestAuthorizationIfNeeded() else { return }

            let settings = await notificationSettings()
            apply(settings: settings)
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }
            guard notificationsPresentationAllowed(settings) else {
                lastDeliveryErrorMessage = "Notifications are authorized but disabled for banners and Notification Center."
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "Jin Notification Test"
            content.subtitle = "Diagnostics"
            content.body = "If you can see this, local notifications are working."
            content.sound = .default
            content.threadIdentifier = "jin.diagnostics"
            if #available(macOS 12.0, *) {
                content.interruptionLevel = .active
            }

            let request = UNNotificationRequest(
                identifier: "jin.test.\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )

            do {
                try await addNotificationRequest(request)
                lastDeliveryErrorMessage = nil
            } catch {
                lastDeliveryErrorMessage = "Notification delivery failed: \(error.localizedDescription)"
            }
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
            apply(settings: settings)
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                if settings.authorizationStatus == .notDetermined {
                    lastDeliveryErrorMessage = "Open Jin and allow notifications first."
                } else {
                    lastDeliveryErrorMessage = "Notifications are disabled for Jin in System Settings."
                }
                return
            }

            guard notificationsPresentationAllowed(settings) else {
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
            if #available(macOS 12.0, *) {
                content.interruptionLevel = .active
            }

            let request = UNNotificationRequest(
                identifier: "jin.reply.\(conversationID.uuidString).\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )

            do {
                try await addNotificationRequest(request)
                lastDeliveryErrorMessage = nil
            } catch {
                lastDeliveryErrorMessage = "Notification delivery failed: \(error.localizedDescription)"
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

    private func apply(settings: UNNotificationSettings) {
        authorizationStatus = settings.authorizationStatus
        diagnosticsSummary =
            "Authorization: \(settings.authorizationStatus.diagnosticsLabel), " +
            "Alert: \(settings.alertSetting.diagnosticsLabel), " +
            "Notification Center: \(settings.notificationCenterSetting.diagnosticsLabel), " +
            "Sound: \(settings.soundSetting.diagnosticsLabel), " +
            "Pending: \(pendingRequestCount), " +
            "Delivered: \(deliveredNotificationCount), " +
            "Last ID: \(lastScheduledNotificationID ?? "none")"
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
        lastScheduledNotificationID = request.identifier
        await refreshQueueDiagnostics()
    }

    private func notificationsPresentationAllowed(_ settings: UNNotificationSettings) -> Bool {
        let alertAllowed = settings.alertSetting == .enabled || settings.alertSetting == .notSupported
        let centerAllowed = settings.notificationCenterSetting == .enabled || settings.notificationCenterSetting == .notSupported
        return alertAllowed || centerAllowed
    }

    private func refreshQueueDiagnostics() async {
        async let pending = pendingNotificationRequests()
        async let delivered = deliveredNotifications()
        let pendingList = await pending
        let deliveredList = await delivered
        pendingRequestCount = pendingList.count
        deliveredNotificationCount = deliveredList.count
        let settings = await notificationSettings()
        apply(settings: settings)
    }

    private func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    private func deliveredNotifications() async -> [UNNotification] {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications)
            }
        }
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

private extension UNAuthorizationStatus {
    var diagnosticsLabel: String {
        switch self {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown"
        }
    }
}

private extension UNNotificationSetting {
    var diagnosticsLabel: String {
        switch self {
        case .notSupported: return "notSupported"
        case .disabled: return "disabled"
        case .enabled: return "enabled"
        @unknown default: return "unknown"
        }
    }
}
