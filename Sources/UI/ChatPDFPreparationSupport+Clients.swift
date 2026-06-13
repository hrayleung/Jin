import Foundation

extension ChatMessagePreparationSupport {
    struct PDFPreparationClients {
        let mistralClient: MistralOCRClient?
        let mineruClient: MinerUOCRClient?
        let deepSeekClient: DeepInfraDeepSeekOCRClient?
        let openRouterClient: OpenRouterOCRClient?
        let firecrawlClient: FirecrawlPDFOCRClient?
        let r2Uploader: CloudflareR2Uploader?

        static let empty = PDFPreparationClients(
            mistralClient: nil,
            mineruClient: nil,
            deepSeekClient: nil,
            openRouterClient: nil,
            firecrawlClient: nil,
            r2Uploader: nil
        )
    }

    /// Reads a string preference, trims it, and returns the trimmed value.
    /// Throws `missing` if the key is absent or blank after trimming.
    static func requiredTrimmedCredential(
        forKey key: String,
        defaults: UserDefaults,
        missing: PDFProcessingError
    ) throws -> String {
        let raw = defaults.string(forKey: key)
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw missing }
        return trimmed
    }

    static func makePDFPreparationClients(
        pdfCount: Int,
        requestedMode: PDFProcessingMode,
        defaults: UserDefaults = .standard
    ) throws -> PDFPreparationClients {
        guard pdfCount > 0 else { return .empty }

        return PDFPreparationClients(
            mistralClient: try makeMistralClientIfNeeded(requestedMode: requestedMode, defaults: defaults),
            mineruClient: try makeMinerUClientIfNeeded(requestedMode: requestedMode, defaults: defaults),
            deepSeekClient: try makeDeepSeekClientIfNeeded(requestedMode: requestedMode, defaults: defaults),
            openRouterClient: try makeOpenRouterClientIfNeeded(requestedMode: requestedMode, defaults: defaults),
            firecrawlClient: try makeFirecrawlClientIfNeeded(requestedMode: requestedMode, defaults: defaults),
            r2Uploader: try makeCloudflareR2UploaderIfNeeded(requestedMode: requestedMode, defaults: defaults)
        )
    }

    private static func makeMistralClientIfNeeded(
        requestedMode: PDFProcessingMode,
        defaults: UserDefaults
    ) throws -> MistralOCRClient? {
        guard requestedMode == .mistralOCR else { return nil }
        let apiKey = try requiredTrimmedCredential(
            forKey: AppPreferenceKeys.pluginMistralOCRAPIKey,
            defaults: defaults,
            missing: .mistralAPIKeyMissing
        )
        return MistralOCRClient(apiKey: apiKey)
    }

    private static func makeMinerUClientIfNeeded(
        requestedMode: PDFProcessingMode,
        defaults: UserDefaults
    ) throws -> MinerUOCRClient? {
        guard requestedMode == .mineruOCR else { return nil }
        let apiToken = try requiredTrimmedCredential(
            forKey: AppPreferenceKeys.pluginMineruOCRAPIToken,
            defaults: defaults,
            missing: .mineruAPITokenMissing
        )
        let userIdentifier = defaults.string(forKey: AppPreferenceKeys.pluginMineruOCRUserIdentifier)
        let trimmedUserIdentifier = userIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        return MinerUOCRClient(apiToken: apiToken, userToken: trimmedUserIdentifier)
    }

    private static func makeDeepSeekClientIfNeeded(
        requestedMode: PDFProcessingMode,
        defaults: UserDefaults
    ) throws -> DeepInfraDeepSeekOCRClient? {
        guard requestedMode == .deepSeekOCR else { return nil }
        let apiKey = try requiredTrimmedCredential(
            forKey: AppPreferenceKeys.pluginDeepSeekOCRAPIKey,
            defaults: defaults,
            missing: .deepInfraAPIKeyMissing
        )
        return DeepInfraDeepSeekOCRClient(apiKey: apiKey)
    }

    private static func makeOpenRouterClientIfNeeded(
        requestedMode: PDFProcessingMode,
        defaults: UserDefaults
    ) throws -> OpenRouterOCRClient? {
        guard requestedMode == .openRouterOCR else { return nil }
        let apiKey = try requiredTrimmedCredential(
            forKey: AppPreferenceKeys.pluginOpenRouterOCRAPIKey,
            defaults: defaults,
            missing: .openRouterOCRAPIKeyMissing
        )
        let modelID = OpenRouterOCRModelCatalog.normalizedModelID(
            defaults.string(forKey: AppPreferenceKeys.pluginOpenRouterOCRModelID)
        )
        return OpenRouterOCRClient(apiKey: apiKey, modelID: modelID)
    }

    private static func makeFirecrawlClientIfNeeded(
        requestedMode: PDFProcessingMode,
        defaults: UserDefaults
    ) throws -> FirecrawlPDFOCRClient? {
        guard requestedMode == .firecrawlOCR else { return nil }
        let apiKey = try requiredTrimmedCredential(
            forKey: AppPreferenceKeys.pluginWebSearchFirecrawlAPIKey,
            defaults: defaults,
            missing: .firecrawlAPIKeyMissing
        )
        return FirecrawlPDFOCRClient(apiKey: apiKey)
    }
}

extension ChatMessagePreparationSupport {
    private static func makeCloudflareR2UploaderIfNeeded(
        requestedMode: PDFProcessingMode,
        defaults: UserDefaults
    ) throws -> CloudflareR2Uploader? {
        guard requestedMode == .firecrawlOCR else { return nil }
        guard AppPreferences.isPluginEnabled("cloudflare_r2_upload", defaults: defaults) else {
            throw LLMError.invalidRequest(
                message: "Firecrawl OCR requires Cloudflare R2 Upload to be enabled in Settings → Plugins."
            )
        }
        return CloudflareR2Uploader(defaults: defaults)
    }
}
