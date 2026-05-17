import Foundation

extension ChatMessagePreparationSupport {
    struct MessagePreparationProfile {
        let modelName: String
        let supportsVideoGenerationControl: Bool
        let supportsVideoInput: Bool
        let supportsMediaGenerationControl: Bool
        let supportsNativePDF: Bool
        let supportsVision: Bool
        let pdfProcessingMode: PDFProcessingMode
        let firecrawlPDFParserMode: FirecrawlPDFParserMode
    }

    struct PreparedPDFContent {
        let extractedText: String?
        let additionalParts: [ContentPart]
    }
}
