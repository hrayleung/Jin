import Combine
import Foundation

/// Process-wide plugin enablement / credential snapshot.
///
/// `ChatView` remounts on every conversation (`.id(conversation.id)`). Local
/// `@State` defaults (`webSearchPluginConfigured = false`) therefore hid the
/// Web Search globe until a post-appear `.task` hopped back to the main actor.
/// This store is seeded synchronously at launch and reused across remounts so
/// the first committed composer frame already has the right icons.
@MainActor
final class ChatExtensionCredentialStore: ObservableObject {
    @Published private(set) var status: ChatExtensionCredentialStatus

    private let defaults: UserDefaults
    private var credentialsChangeCancellable: AnyCancellable?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        status = ChatConversationStateSupport.resolveExtensionCredentialStatus(defaults: defaults)
        credentialsChangeCancellable = NotificationCenter.default
            .publisher(for: .pluginCredentialsDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    func refresh() {
        let next = ChatConversationStateSupport.resolveExtensionCredentialStatus(defaults: defaults)
        guard next != status else { return }
        status = next
    }
}
