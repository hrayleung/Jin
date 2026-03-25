import Foundation

enum AppPreferencesSnapshotStore {
    private static let legacyDomainNames = ["Jin"]
    private static let canonicalDomainName = AppDataLocations.sharedDirectoryName

    static func currentDomainName(defaults: UserDefaults = .standard) -> String {
        Bundle.main.bundleIdentifier
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? canonicalDomainName
    }

    static func prepareSharedPreferencesAtLaunch(defaults: UserDefaults = .standard) {
        let domainName = currentDomainName(defaults: defaults)
        let before = defaults.persistentDomain(forName: domainName) ?? [:]
        let beforeKeys = Set(before.keys)

        logPreferenceDiagnostic("=== prepareSharedPreferencesAtLaunch START ===")
        logPreferenceDiagnostic("domain=\(domainName) keys_before=\(beforeKeys.count)")
        logPluginKeySnapshot("BEFORE", defaults: defaults)

        let merged = recoveredPreferenceDictionaryIfNeeded(
            currentPreferences: mergedPreferenceDictionary(defaults: defaults)
        )
        logPreferenceDiagnostic("merged_keys=\(merged.count)")

        guard !merged.isEmpty else {
            logPreferenceDiagnostic("merged is empty, skipping apply")
            return
        }

        applyPreferenceDictionary(merged, defaults: defaults)

        let after = defaults.persistentDomain(forName: domainName) ?? [:]
        let afterKeys = Set(after.keys)
        let lostKeys = beforeKeys.subtracting(afterKeys)

        if !lostKeys.isEmpty {
            logPreferenceDiagnostic("LOST \(lostKeys.count) keys: \(lostKeys.sorted())")
            for key in lostKeys {
                if let value = before[key] {
                    defaults.set(value, forKey: key)
                }
            }
            defaults.synchronize()
            logPreferenceDiagnostic("restored \(lostKeys.count) lost keys")
        }

        logPluginKeySnapshot("AFTER", defaults: defaults)
        logPreferenceDiagnostic("=== prepareSharedPreferencesAtLaunch END keys_after=\(afterKeys.count) ===")
    }

    static func mergedPreferenceDictionary(
        defaults: UserDefaults = .standard,
        currentDomainOverride: String? = nil
    ) -> [String: Any] {
        var merged: [String: Any] = [:]
        let domains = mergeOrderDomainNames(defaults: defaults, currentDomainOverride: currentDomainOverride)

        for domainName in domains {
            if let onDisk = loadSystemPreferencesPlist(for: domainName) {
                logPreferenceDiagnostic("source:onDiskPlist(\(domainName)) keys=\(onDisk.count)")
                merged.merge(onDisk, uniquingKeysWith: { _, newer in newer })
            } else {
                logPreferenceDiagnostic("source:onDiskPlist(\(domainName)) NOT_FOUND")
            }
        }

        if let sharedDictionary = loadPreferenceDictionary(from: try? AppDataLocations.sharedPreferencesFileURL()) {
            logPreferenceDiagnostic("source:sharedPlist keys=\(sharedDictionary.count)")
            merged.merge(sharedDictionary, uniquingKeysWith: { _, newer in newer })
        } else {
            logPreferenceDiagnostic("source:sharedPlist NOT_FOUND")
        }

        for domainName in domains {
            if let dictionary = defaults.persistentDomain(forName: domainName) {
                logPreferenceDiagnostic("source:persistentDomain(\(domainName)) keys=\(dictionary.count)")
                merged.merge(dictionary, uniquingKeysWith: { _, newer in newer })
            } else {
                logPreferenceDiagnostic("source:persistentDomain(\(domainName)) NIL")
            }
        }

        return merged
    }

    @discardableResult
    static func persistCurrentDomain(defaults: UserDefaults = .standard) -> Bool {
        let currentDomain = currentDomainName(defaults: defaults)
        let currentDictionary = defaults.persistentDomain(forName: currentDomain) ?? [:]
        guard !currentDictionary.isEmpty else { return false }
        return persistPreferenceDictionary(currentDictionary)
    }

    @discardableResult
    static func persistMergedPreferences(defaults: UserDefaults = .standard) -> Bool {
        persistPreferenceDictionary(mergedPreferenceDictionary(defaults: defaults))
    }

    static func persistPreferenceDictionary(_ dictionary: [String: Any]) -> Bool {
        guard !dictionary.isEmpty else { return false }
        guard let sharedURL = try? AppDataLocations.sharedPreferencesFileURL() else { return false }
        guard let parentDirectory = try? AppDataLocations.preferencesDirectoryURL() else { return false }
        if !FileManager.default.fileExists(atPath: parentDirectory.path) {
            try? FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        }

        do {
            let data = try preferenceData(for: dictionary)
            try data.write(to: sharedURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func snapshotPreferences() -> [String: Any] {
        mergedPreferenceDictionary()
    }

    static func snapshotPreferenceData() throws -> Data {
        try preferenceData(for: snapshotPreferences())
    }

    static func preferenceData(for dictionary: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .xml,
            options: 0
        )
    }

    static func applyPreferenceDictionary(_ dictionary: [String: Any], defaults: UserDefaults = .standard) {
        for (key, value) in dictionary {
            defaults.set(value, forKey: key)
        }
        defaults.synchronize()
        _ = persistMergedPreferences(defaults: defaults)
    }

    static func applyPreferenceFile(at url: URL, defaults: UserDefaults = .standard) {
        guard let dictionary = loadPreferenceDictionary(from: url) else { return }
        applyPreferenceDictionary(dictionary, defaults: defaults)
    }

    static func loadPreferenceDictionary(from url: URL?) -> [String: Any]? {
        guard let url else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = propertyList as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    private static let pluginDiagnosticKeys = [
        AppPreferenceKeys.pluginWebSearchExaAPIKey,
        AppPreferenceKeys.pluginMistralOCRAPIKey,
        AppPreferenceKeys.pluginDeepSeekOCRAPIKey,
        AppPreferenceKeys.ttsGroqAPIKey,
        AppPreferenceKeys.sttGroqAPIKey,
        AppPreferenceKeys.cloudflareR2AccountID,
        AppPreferenceKeys.pluginWebSearchTavilyAPIKey,
        AppPreferenceKeys.ttsProvider,
        AppPreferenceKeys.pluginChatNamingEnabled
    ]

    private static func logPluginKeySnapshot(_ label: String, defaults: UserDefaults) {
        for key in pluginDiagnosticKeys {
            let val = defaults.object(forKey: key)
            let present = val != nil ? "SET(\(type(of: val!)))" : "NIL"
            logPreferenceDiagnostic("  \(label) \(key) = \(present)")
        }
    }

    static func logPreferenceDiagnostic(_ message: String) {
        NSLog("[Jin.Prefs] %@", message)
        guard let logDir = try? AppDataLocations.logsDirectoryURL() else { return }
        let logFile = logDir.appendingPathComponent("preference-debug.log", isDirectory: false)
        if !FileManager.default.fileExists(atPath: logDir.path) {
            try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFile, options: .atomic)
            }
        }
    }

    private static func loadSystemPreferencesPlist(for domainName: String) -> [String: Any]? {
        guard let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty else { return nil }
        let plistURL = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Preferences/\(domainName).plist", isDirectory: false)
        return loadPreferenceDictionary(from: plistURL)
    }

    private static func recoveredPreferenceDictionaryIfNeeded(
        currentPreferences: [String: Any]
    ) -> [String: Any] {
        guard let snapshotPreferences = latestHealthySnapshotPreferenceDictionary() else {
            return currentPreferences
        }

        let currentManaged = managedPreferenceDictionary(from: currentPreferences)
        let snapshotManaged = managedPreferenceDictionary(from: snapshotPreferences)
        let missingManagedKeys = Set(snapshotManaged.keys).subtracting(currentManaged.keys)

        guard shouldRecoverFromSnapshot(
            currentManagedCount: currentManaged.count,
            snapshotManagedCount: snapshotManaged.count,
            missingManagedCount: missingManagedKeys.count
        ) else {
            return currentPreferences
        }

        logPreferenceDiagnostic(
            "recovering_preferences_from_snapshot current_managed=\(currentManaged.count) snapshot_managed=\(snapshotManaged.count) restored_missing=\(missingManagedKeys.count)"
        )
        return snapshotPreferences.merging(currentPreferences, uniquingKeysWith: { _, current in current })
    }

    private static func latestHealthySnapshotPreferenceDictionary() -> [String: Any]? {
        guard let snapshot = AppSnapshotManager.latestHealthySnapshot(),
              snapshot.manifest.hasPreferences else {
            return nil
        }

        let preferencesURL = snapshot.directoryURL
            .appendingPathComponent("Preferences", isDirectory: true)
            .appendingPathComponent(AppDataLocations.snapshotPreferencesFileName, isDirectory: false)
        return loadPreferenceDictionary(from: preferencesURL)
    }

    private static func managedPreferenceDictionary(from dictionary: [String: Any]) -> [String: Any] {
        dictionary.filter { isManagedPreferenceKey($0.key) }
    }

    private static func isManagedPreferenceKey(_ key: String) -> Bool {
        !key.hasPrefix("NS") && !key.hasPrefix("SU")
    }

    private static func shouldRecoverFromSnapshot(
        currentManagedCount: Int,
        snapshotManagedCount: Int,
        missingManagedCount: Int
    ) -> Bool {
        guard snapshotManagedCount >= 10 else { return false }
        guard missingManagedCount >= 8 else { return false }
        return currentManagedCount <= 5 || snapshotManagedCount >= currentManagedCount * 3
    }

    private static func mergeOrderDomainNames(
        defaults: UserDefaults,
        currentDomainOverride: String? = nil
    ) -> [String] {
        let current = currentDomainOverride ?? currentDomainName(defaults: defaults)
        let legacyNames = legacyDomainNames.filter { $0 != canonicalDomainName }
        return [canonicalDomainName] + legacyNames + [current]
    }
}

final class AppPreferencesSyncController {
    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?
    private var pendingFlushTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        AppPreferencesSnapshotStore.prepareSharedPreferencesAtLaunch(defaults: defaults)
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: nil
        ) { [weak self] _ in
            self?.scheduleFlush()
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        pendingFlushTask?.cancel()
    }

    func flushNow() {
        pendingFlushTask?.cancel()
        pendingFlushTask = nil
        _ = AppPreferencesSnapshotStore.persistCurrentDomain(defaults: defaults)
    }

    private func scheduleFlush() {
        pendingFlushTask?.cancel()
        pendingFlushTask = Task { [defaults] in
            try? await Task.sleep(for: .seconds(1))
            _ = AppPreferencesSnapshotStore.persistCurrentDomain(defaults: defaults)
        }
    }
}
