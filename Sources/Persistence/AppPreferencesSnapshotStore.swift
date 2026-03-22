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
        let merged = mergedPreferenceDictionary(defaults: defaults)
        guard !merged.isEmpty else { return }
        applyPreferenceDictionary(merged, defaults: defaults)
    }

    static func mergedPreferenceDictionary(
        defaults: UserDefaults = .standard,
        currentDomainOverride: String? = nil
    ) -> [String: Any] {
        var merged: [String: Any] = [:]

        if let sharedDictionary = loadPreferenceDictionary(from: try? AppDataLocations.sharedPreferencesFileURL()) {
            merged.merge(sharedDictionary, uniquingKeysWith: { _, newer in newer })
        }

        for domainName in mergeOrderDomainNames(defaults: defaults, currentDomainOverride: currentDomainOverride) {
            guard let dictionary = defaults.persistentDomain(forName: domainName) else { continue }
            merged.merge(dictionary, uniquingKeysWith: { _, newer in newer })
        }

        return merged
    }

    @discardableResult
    static func persistCurrentDomain(defaults: UserDefaults = .standard) -> Bool {
        let currentDomain = currentDomainName(defaults: defaults)
        let dictionary = defaults.persistentDomain(forName: currentDomain) ?? [:]
        return persistPreferenceDictionary(dictionary)
    }

    @discardableResult
    static func persistMergedPreferences(defaults: UserDefaults = .standard) -> Bool {
        persistPreferenceDictionary(mergedPreferenceDictionary(defaults: defaults))
    }

    static func persistPreferenceDictionary(_ dictionary: [String: Any]) -> Bool {
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
        let domainName = currentDomainName(defaults: defaults)
        defaults.setPersistentDomain(dictionary, forName: domainName)
        defaults.synchronize()
        _ = persistPreferenceDictionary(dictionary)
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
