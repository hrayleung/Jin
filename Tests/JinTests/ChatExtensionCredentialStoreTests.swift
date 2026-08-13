import Combine
import XCTest
@testable import Jin

@MainActor
final class ChatExtensionCredentialStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ChatExtensionCredentialStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testInitReadsConfiguredWebSearchWithoutRefresh() {
        defaults.set(true, forKey: AppPreferenceKeys.pluginWebSearchEnabled)
        defaults.set("exa-test-key", forKey: AppPreferenceKeys.pluginWebSearchExaAPIKey)

        let store = ChatExtensionCredentialStore(defaults: defaults)

        XCTAssertTrue(store.status.webSearchPluginEnabled)
        XCTAssertTrue(store.status.webSearchPluginConfigured)
        XCTAssertTrue(
            ChatAuxiliaryControlSupport.supportsBuiltinSearchPluginControl(
                modelSupportsBuiltinSearchPluginControl: true,
                webSearchPluginEnabled: store.status.webSearchPluginEnabled,
                webSearchPluginConfigured: store.status.webSearchPluginConfigured
            )
        )
    }

    func testInitKeepsWebSearchHiddenWhenUnconfigured() {
        defaults.set(true, forKey: AppPreferenceKeys.pluginWebSearchEnabled)

        let store = ChatExtensionCredentialStore(defaults: defaults)

        XCTAssertTrue(store.status.webSearchPluginEnabled)
        XCTAssertFalse(store.status.webSearchPluginConfigured)
        XCTAssertFalse(
            ChatAuxiliaryControlSupport.supportsBuiltinSearchPluginControl(
                modelSupportsBuiltinSearchPluginControl: true,
                webSearchPluginEnabled: store.status.webSearchPluginEnabled,
                webSearchPluginConfigured: store.status.webSearchPluginConfigured
            )
        )
    }

    func testInitHidesSpeechToTextWhenPluginDisabled() {
        defaults.set(false, forKey: AppPreferenceKeys.pluginSpeechToTextEnabled)

        let store = ChatExtensionCredentialStore(defaults: defaults)

        XCTAssertFalse(store.status.speechToTextPluginEnabled)
    }

    func testRefreshPicksUpNewlyConfiguredWebSearch() {
        let store = ChatExtensionCredentialStore(defaults: defaults)
        XCTAssertFalse(store.status.webSearchPluginConfigured)

        defaults.set(true, forKey: AppPreferenceKeys.pluginWebSearchEnabled)
        defaults.set("brave-key", forKey: AppPreferenceKeys.pluginWebSearchBraveAPIKey)
        store.refresh()

        XCTAssertTrue(store.status.webSearchPluginConfigured)
    }

    func testNotificationRefreshesStore() async {
        let store = ChatExtensionCredentialStore(defaults: defaults)
        XCTAssertFalse(store.status.webSearchPluginConfigured)

        let statusUpdated = expectation(description: "credential status refreshes")
        let cancellable = store.$status
            .dropFirst()
            .sink { status in
                if status.webSearchPluginConfigured {
                    statusUpdated.fulfill()
                }
            }

        defaults.set(true, forKey: AppPreferenceKeys.pluginWebSearchEnabled)
        defaults.set("jina-key", forKey: AppPreferenceKeys.pluginWebSearchJinaAPIKey)
        NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)

        await fulfillment(of: [statusUpdated], timeout: 1)
        XCTAssertTrue(store.status.webSearchPluginConfigured)
        _ = cancellable
    }

    func testInitialControlsDecodeConversationBlob() {
        var controls = GenerationControls()
        controls.webSearch = WebSearchControls(enabled: true)
        let data = try! JSONEncoder().encode(controls)

        let decoded = ChatView.initialControls(from: data)
        XCTAssertEqual(decoded.webSearch?.enabled, true)
        XCTAssertNil(ChatView.initialControls(from: Data()).webSearch)
    }
}
