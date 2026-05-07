import Foundation

extension ChatModelCapabilitySupport {
    static func pdfProcessingBadgeText(mode: PDFProcessingMode) -> String? {
        switch mode {
        case .native:
            return nil
        case .mistralOCR:
            return "OCR"
        case .mineruOCR:
            return "MU"
        case .deepSeekOCR:
            return "DS"
        case .openRouterOCR:
            return "OR"
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
        firecrawlOCRConfigured: Bool
    ) -> String {
        switch mode {
        case .native:
            return "PDF handling: Native"
        case .mistralOCR:
            return mistralOCRConfigured ? "PDF handling: Mistral OCR" : "PDF handling: Mistral OCR (API key required)"
        case .mineruOCR:
            return mineruOCRConfigured ? "PDF handling: MinerU OCR" : "PDF handling: MinerU OCR (API token required)"
        case .deepSeekOCR:
            return deepSeekOCRConfigured ? "PDF handling: DeepSeek OCR (DeepInfra)" : "PDF handling: DeepSeek OCR (API key required)"
        case .openRouterOCR:
            return openRouterOCRConfigured ? "PDF handling: OpenRouter OCR" : "PDF handling: OpenRouter OCR (API key required)"
        case .firecrawlOCR:
            let parserMode = firecrawlParserMode.displayName
            if firecrawlOCRConfigured {
                return "PDF handling: Firecrawl OCR (\(parserMode))"
            }
            return "PDF handling: Firecrawl OCR (\(parserMode), Firecrawl API key + Cloudflare R2 required)"
        case .macOSExtract:
            return "PDF handling: macOS Extract"
        }
    }
}
