import Foundation

extension ChatMessagePreparationSupport {
    struct ThreadPreparedUserMessage {
        let threadID: UUID
        let parts: [ContentPart]
    }

    struct MessagePreparationProfile {
        let threadID: UUID
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
