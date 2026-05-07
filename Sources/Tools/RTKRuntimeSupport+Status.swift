import Foundation

extension RTKRuntimeSupport {
    static func status() async -> RTKRuntimeStatus {
        let configResolution = Result { try RTKConfigManager.configurationFileURL() }
        let teeResolution = Result { try RTKConfigManager.teeDirectoryURL() }
        let configURL = try? configResolution.get()
        let teeDirectoryURL = try? teeResolution.get()
        let configurationErrorDescription = mergedErrorDescription(
            configResolution.failure?.localizedDescription,
            teeResolution.failure?.localizedDescription
        )

        do {
            let helperURL = try helperExecutableURL()
            let version = try await versionString()
            return RTKRuntimeStatus(
                helperURL: helperURL,
                helperVersion: version,
                configURL: configURL,
                teeDirectoryURL: teeDirectoryURL,
                errorDescription: configurationErrorDescription
            )
        } catch {
            return RTKRuntimeStatus(
                helperURL: helperExecutableURLIfAvailable(),
                helperVersion: nil,
                configURL: configURL,
                teeDirectoryURL: teeDirectoryURL,
                errorDescription: mergedErrorDescription(
                    error.localizedDescription,
                    configurationErrorDescription
                )
            )
        }
    }

    private static func mergedErrorDescription(_ first: String?, _ second: String?) -> String? {
        let values = [first, second]
            .compactMap { $0?.trimmedNonEmpty }
        guard !values.isEmpty else { return nil }
        return Array(NSOrderedSet(array: values)).compactMap { $0 as? String }.joined(separator: "\n")
    }
}
