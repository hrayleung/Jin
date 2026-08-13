import Foundation

extension ChatModelCapabilitySupport {
    static let mistralOCRModelDisplayName = "mistral-ocr-latest"
    static let deepSeekOCRModelDisplayName = "DeepSeek-OCR"

    /// Composer picker row. Provider name only — the control already means PDF/OCR.
    static func pdfProcessingMenuTitle(mode: PDFProcessingMode) -> String {
        switch mode {
        case .native:
            return "Native"
        case .mistralOCR:
            return "Mistral"
        case .mineruOCR:
            return "MinerU"
        case .deepSeekOCR:
            return "DeepSeek"
        case .openRouterOCR:
            return "OpenRouter"
        case .firecrawlOCR:
            return "Firecrawl"
        case .macOSExtract:
            return "macOS Extract"
        }
    }

    static func pdfProcessingBadgeText(
        mode: PDFProcessingMode,
        openRouterModelID: String? = nil
    ) -> String? {
        switch mode {
        case .native:
            return nil
        case .mistralOCR:
            return "Mist"
        case .mineruOCR:
            return "MinU"
        case .deepSeekOCR:
            return "DS"
        case .openRouterOCR:
            return OpenRouterOCRModelCatalog.resolvedEntry(for: openRouterModelID).composerBadge
        case .firecrawlOCR:
            return "FC"
        case .macOSExtract:
            return "mac"
        }
    }

    static func pdfProcessingHelpText(
        mode: PDFProcessingMode,
        firecrawlParserMode: FirecrawlPDFParserMode,
        mistralOCRConfigured: Bool,
        mineruOCRConfigured: Bool,
        deepSeekOCRConfigured: Bool,
        openRouterOCRConfigured: Bool,
        firecrawlOCRConfigured: Bool,
        openRouterModelName: String? = nil
    ) -> String {
        switch mode {
        case .native:
            return "PDF handling: Native"
        case .mistralOCR:
            let detail = "Mistral \u{00B7} \(mistralOCRModelDisplayName)"
            return mistralOCRConfigured
                ? "PDF handling: \(detail)"
                : "PDF handling: \(detail) (API key required)"
        case .mineruOCR:
            return mineruOCRConfigured
                ? "PDF handling: MinerU"
                : "PDF handling: MinerU (API token required)"
        case .deepSeekOCR:
            let detail = "DeepSeek \u{00B7} \(deepSeekOCRModelDisplayName)"
            return deepSeekOCRConfigured
                ? "PDF handling: \(detail)"
                : "PDF handling: \(detail) (API key required)"
        case .openRouterOCR:
            let model = openRouterModelName
                ?? OpenRouterOCRModelCatalog.defaultEntry.name
            let detail = "OpenRouter \u{00B7} \(model)"
            return openRouterOCRConfigured
                ? "PDF handling: \(detail)"
                : "PDF handling: \(detail) (API key required)"
        case .firecrawlOCR:
            let parserMode = firecrawlParserMode.displayName
            if firecrawlOCRConfigured {
                return "PDF handling: Firecrawl \u{00B7} \(parserMode)"
            }
            return "PDF handling: Firecrawl \u{00B7} \(parserMode) (Firecrawl API key + Cloudflare R2 required)"
        case .macOSExtract:
            return "PDF handling: macOS Extract"
        }
    }
}
