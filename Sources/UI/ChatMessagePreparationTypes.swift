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
        /// Hard cap on page-as-image (and similar) vision parts for this send.
        /// `nil` means no provider-specific cap.
        let maxVisionImagesPerRequest: Int?

        init(
            modelName: String,
            supportsVideoGenerationControl: Bool,
            supportsVideoInput: Bool,
            supportsMediaGenerationControl: Bool,
            supportsNativePDF: Bool,
            supportsVision: Bool,
            pdfProcessingMode: PDFProcessingMode,
            firecrawlPDFParserMode: FirecrawlPDFParserMode,
            maxVisionImagesPerRequest: Int? = nil
        ) {
            self.modelName = modelName
            self.supportsVideoGenerationControl = supportsVideoGenerationControl
            self.supportsVideoInput = supportsVideoInput
            self.supportsMediaGenerationControl = supportsMediaGenerationControl
            self.supportsNativePDF = supportsNativePDF
            self.supportsVision = supportsVision
            self.pdfProcessingMode = pdfProcessingMode
            self.firecrawlPDFParserMode = firecrawlPDFParserMode
            self.maxVisionImagesPerRequest = maxVisionImagesPerRequest
        }
    }

    struct PreparedPDFContent {
        let extractedText: String?
        let additionalParts: [ContentPart]
    }
}
