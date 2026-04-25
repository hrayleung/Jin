import XCTest
@testable import Jin

final class AppPreferencesSnapshotStoreTests: PreferencesSandboxedTestCase {
    func testCurrentDomainOverridesLegacyJinDomain() {
        let suiteName = "AppPreferencesSnapshotStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let currentDomain = "AppPreferencesSnapshotStoreTests.current.\(UUID().uuidString)"
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            defaults.removePersistentDomain(forName: "Jin")
            defaults.removePersistentDomain(forName: currentDomain)
        }

        defaults.setPersistentDomain(["sharedKey": "legacy"], forName: "Jin")
        defaults.setPersistentDomain(["sharedKey": "current"], forName: currentDomain)

        let merged = AppPreferencesSnapshotStore.mergedPreferenceDictionary(
            defaults: defaults,
            currentDomainOverride: currentDomain
        )
        XCTAssertEqual(merged["sharedKey"] as? String, "current")
    }

    func testCanonicalReleaseDomainStillWinsOverLegacyJinDomain() {
        let suiteName = "AppPreferencesSnapshotStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: "com.jin.app")
            defaults.removePersistentDomain(forName: "Jin")
        }

        defaults.setPersistentDomain(["sharedKey": "release"], forName: "com.jin.app")
        defaults.setPersistentDomain(["sharedKey": "legacy"], forName: "Jin")

        let merged = AppPreferencesSnapshotStore.mergedPreferenceDictionary(
            defaults: defaults,
            currentDomainOverride: "com.jin.app"
        )
        XCTAssertEqual(merged["sharedKey"] as? String, "release")
    }

    func testApplyPreferenceDictionaryMergesInsteadOfReplacing() {
        let defaults = UserDefaults.standard
        let domainName = AppPreferencesSnapshotStore.currentDomainName(defaults: defaults)
        let preserved = defaults.persistentDomain(forName: domainName)
        defer {
            if let preserved {
                defaults.setPersistentDomain(preserved, forName: domainName)
            } else {
                defaults.removePersistentDomain(forName: domainName)
            }
        }

        defaults.setPersistentDomain([
            "existingKey": "existingValue",
            "sharedKey": "old"
        ], forName: domainName)

        AppPreferencesSnapshotStore.applyPreferenceDictionary(
            ["sharedKey": "new", "newKey": "newValue"],
            defaults: defaults
        )

        let domain = defaults.persistentDomain(forName: domainName)
        XCTAssertEqual(domain?["existingKey"] as? String, "existingValue",
                        "Existing keys not in the applied dictionary must survive")
        XCTAssertEqual(domain?["sharedKey"] as? String, "new",
                        "Incoming keys must override existing values")
        XCTAssertEqual(domain?["newKey"] as? String, "newValue",
                        "New keys from the applied dictionary must be added")
    }

    func testPersistPreferenceDictionaryRefusesEmptyDictionary() {
        let result = AppPreferencesSnapshotStore.persistPreferenceDictionary([:])
        XCTAssertFalse(result, "persistPreferenceDictionary must refuse to write an empty dictionary")
    }

    func testPersistCurrentDomainRefusesEmptyDomain() {
        let suiteName = "AppPreferencesSnapshotStoreTests.empty.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.removePersistentDomain(forName: AppPreferencesSnapshotStore.currentDomainName(defaults: defaults))

        let result = AppPreferencesSnapshotStore.persistCurrentDomain(defaults: defaults)
        XCTAssertFalse(result, "persistCurrentDomain must refuse when domain is empty")
    }

    func testPrepareSharedPreferencesAtLaunchRecoversManagedPreferencesFromLatestHealthySnapshot() throws {
        let previousAppSupportRoot = ProcessInfo.processInfo.environment["JIN_APP_SUPPORT_ROOT"]
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("jin-prefs-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        setenv("JIN_APP_SUPPORT_ROOT", temporaryRoot.path, 1)
        defer {
            if let previousAppSupportRoot {
                setenv("JIN_APP_SUPPORT_ROOT", previousAppSupportRoot, 1)
            } else {
                unsetenv("JIN_APP_SUPPORT_ROOT")
            }
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        try AppDataLocations.ensureDirectoriesExist()

        let snapshotPreferences: [String: Any] = [
            AppPreferenceKeys.pluginWebSearchExaAPIKey: "exa-restored",
            AppPreferenceKeys.pluginWebSearchTavilyAPIKey: "tavily-restored",
            AppPreferenceKeys.pluginMistralOCRAPIKey: "mistral-restored",
            AppPreferenceKeys.pluginDeepSeekOCRAPIKey: "deepseek-restored",
            AppPreferenceKeys.pluginOpenRouterOCRAPIKey: "openrouter-restored",
            AppPreferenceKeys.pluginOpenRouterOCRModelID: "qwen/qwen3-vl-8b-instruct",
            AppPreferenceKeys.ttsGroqAPIKey: "tts-restored",
            AppPreferenceKeys.sttGroqAPIKey: "stt-restored",
            AppPreferenceKeys.cloudflareR2AccountID: "account-restored",
            AppPreferenceKeys.ttsProvider: "groq",
            AppPreferenceKeys.codeBlockDisplayMode: "collapsible",
            AppPreferenceKeys.codeBlockShowLineNumbers: true,
            AppPreferenceKeys.agentModeEnabled: true,
            AppPreferenceKeys.chatNamingProviderID: "deepseek",
            AppPreferenceKeys.chatNamingModelID: "deepseek-chat"
        ]
        try writeHealthySnapshot(preferences: snapshotPreferences)

        let defaults = UserDefaults.standard
        let domainName = AppPreferencesSnapshotStore.currentDomainName(defaults: defaults)
        let preserved = defaults.persistentDomain(forName: domainName)
        defer {
            if let preserved {
                defaults.setPersistentDomain(preserved, forName: domainName)
            } else {
                defaults.removePersistentDomain(forName: domainName)
            }
        }

        let truncatedPreferences: [String: Any] = [
            "appIconVariant": "E",
            "mcpTransportSchemaVersion": 2,
            AppPreferenceKeys.agentModeEnabled: true
        ]
        defaults.setPersistentDomain(truncatedPreferences, forName: domainName)
        XCTAssertTrue(AppPreferencesSnapshotStore.persistPreferenceDictionary(truncatedPreferences))

        AppPreferencesSnapshotStore.prepareSharedPreferencesAtLaunch(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.pluginWebSearchExaAPIKey), "exa-restored")
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.pluginWebSearchTavilyAPIKey), "tavily-restored")
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.pluginOpenRouterOCRAPIKey), "openrouter-restored")
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.pluginOpenRouterOCRModelID), "qwen/qwen3-vl-8b-instruct")
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.ttsProvider), "groq")
        XCTAssertEqual(defaults.object(forKey: AppPreferenceKeys.codeBlockShowLineNumbers) as? Bool, true)
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.chatNamingProviderID), "deepseek")
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.chatNamingModelID), "deepseek-chat")

        let sharedDictionary = AppPreferencesSnapshotStore.loadPreferenceDictionary(
            from: try AppDataLocations.sharedPreferencesFileURL()
        )
        XCTAssertEqual(sharedDictionary?[AppPreferenceKeys.pluginMistralOCRAPIKey] as? String, "mistral-restored")
        XCTAssertEqual(sharedDictionary?[AppPreferenceKeys.pluginOpenRouterOCRAPIKey] as? String, "openrouter-restored")
        XCTAssertEqual(sharedDictionary?[AppPreferenceKeys.cloudflareR2AccountID] as? String, "account-restored")
    }

    private func writeHealthySnapshot(preferences: [String: Any]) throws {
        let snapshotDirectory = try AppDataLocations.snapshotsDirectoryURL()
            .appendingPathComponent("snapshot-\(UUID().uuidString)", isDirectory: true)
        let databaseDirectory = snapshotDirectory.appendingPathComponent("Database", isDirectory: true)
        let preferencesDirectory = snapshotDirectory.appendingPathComponent("Preferences", isDirectory: true)
        try FileManager.default.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: preferencesDirectory, withIntermediateDirectories: true)

        let storeURL = databaseDirectory.appendingPathComponent(AppDataLocations.storeFileName, isDirectory: false)
        FileManager.default.createFile(atPath: storeURL.path, contents: Data())

        let manifest = SnapshotManifest(
            id: UUID().uuidString.lowercased(),
            createdAt: Date(),
            reason: .launchHealthy,
            appVersion: "test",
            schemaVersion: 1,
            includesSecrets: true,
            isAutomatic: true,
            isHealthy: true,
            isLegacy: false,
            integrityDetail: "ok",
            counts: SnapshotCoreCounts(conversations: 1, messages: 2, providers: 1, assistants: 1, mcpServers: 0),
            hasAttachments: false,
            hasPreferences: true,
            note: nil
        )
        let manifestURL = snapshotDirectory.appendingPathComponent(
            AppDataLocations.snapshotManifestFileName,
            isDirectory: false
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        let preferencesURL = preferencesDirectory.appendingPathComponent(
            AppDataLocations.snapshotPreferencesFileName,
            isDirectory: false
        )
        try AppPreferencesSnapshotStore.preferenceData(for: preferences).write(to: preferencesURL, options: .atomic)
    }

}
