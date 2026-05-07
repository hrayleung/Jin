import Foundation

extension ChatModelCapabilitySupport {
    static func setPDFProcessingMode(
        _ mode: PDFProcessingMode,
        controls: GenerationControls
    ) -> GenerationControls {
        var controls = controls
        controls.pdfProcessingMode = (mode == .native) ? nil : mode
        return controls
    }

    static func setFirecrawlPDFParserMode(
        _ mode: FirecrawlPDFParserMode,
        controls: GenerationControls
    ) -> GenerationControls {
        var controls = controls
        controls.firecrawlPDFParserMode = (mode == .ocr) ? nil : mode
        return controls
    }

    static func defaultPDFProcessingFallbackMode(
        mistralOCRPluginEnabled: Bool,
        mistralOCRConfigured: Bool,
        mineruOCRPluginEnabled: Bool,
        mineruOCRConfigured: Bool,
        deepSeekOCRPluginEnabled: Bool,
        deepSeekOCRConfigured: Bool,
        openRouterOCRPluginEnabled: Bool,
        openRouterOCRConfigured: Bool,
        firecrawlOCRPluginEnabled: Bool,
        firecrawlOCRConfigured: Bool
    ) -> PDFProcessingMode {
        if mistralOCRPluginEnabled, mistralOCRConfigured {
            return .mistralOCR
        }
        if mineruOCRPluginEnabled, mineruOCRConfigured {
            return .mineruOCR
        }
        if deepSeekOCRPluginEnabled, deepSeekOCRConfigured {
            return .deepSeekOCR
        }
        if openRouterOCRPluginEnabled, openRouterOCRConfigured {
            return .openRouterOCR
        }
        if firecrawlOCRPluginEnabled, firecrawlOCRConfigured {
            return .firecrawlOCR
        }
        return .macOSExtract
    }

    static func isPDFProcessingModeAvailable(
        _ mode: PDFProcessingMode,
        supportsNativePDF: Bool,
        mistralOCRPluginEnabled: Bool,
        mineruOCRPluginEnabled: Bool,
        deepSeekOCRPluginEnabled: Bool,
        openRouterOCRPluginEnabled: Bool,
        firecrawlOCRPluginEnabled: Bool
    ) -> Bool {
        switch mode {
        case .native:
            return supportsNativePDF
        case .macOSExtract:
            return true
        case .mistralOCR:
            return mistralOCRPluginEnabled
        case .mineruOCR:
            return mineruOCRPluginEnabled
        case .deepSeekOCR:
            return deepSeekOCRPluginEnabled
        case .openRouterOCR:
            return openRouterOCRPluginEnabled
        case .firecrawlOCR:
            return firecrawlOCRPluginEnabled
        }
    }

    static func resolvedPDFProcessingMode(
        controls: GenerationControls,
        supportsNativePDF: Bool,
        defaultPDFProcessingFallbackMode: PDFProcessingMode,
        mistralOCRPluginEnabled: Bool,
        mineruOCRPluginEnabled: Bool,
        deepSeekOCRPluginEnabled: Bool,
        openRouterOCRPluginEnabled: Bool,
        firecrawlOCRPluginEnabled: Bool
    ) -> PDFProcessingMode {
        let requested = controls.pdfProcessingMode ?? .native
        if isPDFProcessingModeAvailable(
            requested,
            supportsNativePDF: supportsNativePDF,
            mistralOCRPluginEnabled: mistralOCRPluginEnabled,
            mineruOCRPluginEnabled: mineruOCRPluginEnabled,
            deepSeekOCRPluginEnabled: deepSeekOCRPluginEnabled,
            openRouterOCRPluginEnabled: openRouterOCRPluginEnabled,
            firecrawlOCRPluginEnabled: firecrawlOCRPluginEnabled
        ) {
            return requested
        }
        if supportsNativePDF {
            return .native
        }
        return defaultPDFProcessingFallbackMode
    }
}
