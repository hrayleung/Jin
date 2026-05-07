import Foundation

extension ChatMessagePreparationSupport {
    struct PDFPreparationClients {
        let mistralClient: MistralOCRClient?
        let mineruClient: MinerUOCRClient?
        let deepSeekClient: DeepInfraDeepSeekOCRClient?
        let openRouterClient: OpenRouterOCRClient?
        let firecrawlClient: FirecrawlPDFOCRClient?
        let r2Uploader: CloudflareR2Uploader?
    }

    static func makePDFPreparationClients(
        pdfCount: Int,
        requestedMode: PDFProcessingMode,
        defaults: UserDefaults = .standard
    ) throws -> PDFPreparationClients {
        guard pdfCount > 0 else {
            return PDFPreparationClients(
                mistralClient: nil,
                mineruClient: nil,
                deepSeekClient: nil,
                openRouterClient: nil,
                firecrawlClient: nil,
                r2Uploader: nil
            )
        }

        return PDFPreparationClients(
            mistralClient: try makeMistralClientIfNeeded(requestedMode: requestedMode, defaults: defaults),
            mineruClient: try makeMinerUClientIfNeeded(requestedMode: requestedMode, defaults: defaults),
            deepSeekClient: try makeDeepSeekClientIfNeeded(requestedMode: requestedMode, defaults: defaults),
            openRouterClient: try makeOpenRouterClientIfNeeded(requestedMode: requestedMode, defaults: defaults),
            firecrawlClient: try makeFirecrawlClientIfNeeded(requestedMode: requestedMode, defaults: defaults),
            r2Uploader: requestedMode == .firecrawlOCR ? CloudflareR2Uploader(defaults: defaults) : nil
        )
    }

    private static func makeMistralClientIfNeeded(
        requestedMode: PDFProcessingMode,
        defaults: UserDefaults
    ) throws -> MistralOCRClient? {
        guard requestedMode == .mistralOCR else { return nil }

        let key = defaults.string(forKey: AppPreferenceKeys.pluginMistralOCRAPIKey)
        let trimmed = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PDFProcessingError.mistralAPIKeyMissing }

        return MistralOCRClient(apiKey: trimmed)
    }

    private static func makeMinerUClientIfNeeded(
        requestedMode: PDFProcessingMode,
        defaults: UserDefaults
    ) throws -> MinerUOCRClient? {
        guard requestedMode == .mineruOCR else { return nil }

        let token = defaults.string(forKey: AppPreferenceKeys.pluginMineruOCRAPIToken)
        let trimmed = (token ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PDFProcessingError.mineruAPITokenMissing }

        let userIdentifier = defaults.string(forKey: AppPreferenceKeys.pluginMineruOCRUserIdentifier)
        let trimmedUserIdentifier = userIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        return MinerUOCRClient(apiToken: trimmed, userToken: trimmedUserIdentifier)
    }

    private static func makeDeepSeekClientIfNeeded(
        requestedMode: PDFProcessingMode,
        defaults: UserDefaults
    ) throws -> DeepInfraDeepSeekOCRClient? {
        guard requestedMode == .deepSeekOCR else { return nil }

        let key = defaults.string(forKey: AppPreferenceKeys.pluginDeepSeekOCRAPIKey)
        let trimmed = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PDFProcessingError.deepInfraAPIKeyMissing }

        return DeepInfraDeepSeekOCRClient(apiKey: trimmed)
    }

    private static func makeOpenRouterClientIfNeeded(
        requestedMode: PDFProcessingMode,
        defaults: UserDefaults
    ) throws -> OpenRouterOCRClient? {
        guard requestedMode == .openRouterOCR else { return nil }

        let key = defaults.string(forKey: AppPreferenceKeys.pluginOpenRouterOCRAPIKey)
        let trimmed = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PDFProcessingError.openRouterOCRAPIKeyMissing }

        let modelID = OpenRouterOCRModelCatalog.normalizedModelID(
            defaults.string(forKey: AppPreferenceKeys.pluginOpenRouterOCRModelID)
        )
        return OpenRouterOCRClient(apiKey: trimmed, modelID: modelID)
    }

    private static func makeFirecrawlClientIfNeeded(
        requestedMode: PDFProcessingMode,
        defaults: UserDefaults
    ) throws -> FirecrawlPDFOCRClient? {
        guard requestedMode == .firecrawlOCR else { return nil }

        let key = defaults.string(forKey: AppPreferenceKeys.pluginWebSearchFirecrawlAPIKey)
        let trimmed = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PDFProcessingError.firecrawlAPIKeyMissing }

        return FirecrawlPDFOCRClient(apiKey: trimmed)
    }
}
