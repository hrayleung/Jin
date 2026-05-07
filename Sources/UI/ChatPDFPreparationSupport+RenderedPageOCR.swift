import Foundation

extension ChatMessagePreparationSupport {
    static func preparedDeepSeekOCRPDF(
        _ attachment: DraftAttachment,
        profile: MessagePreparationProfile,
        totalPDFCount: Int,
        pdfOrdinal: Int,
        deepSeekClient: DeepInfraDeepSeekOCRClient?,
        onStatusUpdate: @MainActor @Sendable (String) -> Void
    ) async throws -> PreparedPDFContent {
        guard let deepSeekClient else { throw PDFProcessingError.deepInfraAPIKeyMissing }

        let includePageImages = profile.supportsVision
        let renderedPages = try PDFKitImageRenderer.renderAllPagesAsJPEG(from: attachment.fileURL)
        let totalPages = max(1, renderedPages.count)

        var pageMarkdown: [String] = []
        pageMarkdown.reserveCapacity(renderedPages.count)

        var imageParts: [ContentPart] = []
        var totalAttachedBytes = 0

        for rendered in renderedPages {
            try Task.checkCancellation()

            await onStatusUpdate("OCR PDF \(pdfOrdinal)/\(max(1, totalPDFCount)) (DeepSeek): \(attachment.filename) — page \(rendered.pageIndex + 1)/\(totalPages)")

            let prompt = "Convert this page to Markdown. Preserve layout and tables. Return only the Markdown."
            let raw = try await deepSeekClient.ocrImage(
                rendered.data,
                mimeType: rendered.mimeType,
                prompt: prompt,
                timeoutSeconds: 120
            )

            let normalized = PDFProcessingUtilities.normalizedDeepSeekOCRMarkdown(raw)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                pageMarkdown.append(normalized)
            }

            if includePageImages,
               imageParts.count < AttachmentConstants.maxMistralOCRImagesToAttach {
                let nextTotal = totalAttachedBytes + rendered.data.count
                if nextTotal <= AttachmentConstants.maxMistralOCRTotalImageBytes {
                    totalAttachedBytes = nextTotal
                    imageParts.append(.image(ImageContent(mimeType: rendered.mimeType, data: rendered.data, url: nil)))
                }
            }
        }

        let combined = pageMarkdown
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !combined.isEmpty else {
            throw PDFProcessingError.noTextExtracted(filename: attachment.filename, method: "DeepSeek OCR (DeepInfra)")
        }

        var output = combined
        if includePageImages, !imageParts.isEmpty {
            let omitted = max(0, renderedPages.count - imageParts.count)
            output += "\n\n[Note: Attached \(imageParts.count) page image(s) for vision context.]"
            if omitted > 0 {
                output += "\n[Note: \(omitted) page image(s) omitted due to size limits.]"
            }
        }

        output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        output = "DeepSeek OCR (Markdown): \(attachment.filename)\n\n\(output)"
        output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.count > AttachmentConstants.maxPDFExtractedCharacters {
            let prefix = output.prefix(AttachmentConstants.maxPDFExtractedCharacters)
            output = "\(prefix)\n\n[Truncated]"
        }
        return PreparedPDFContent(extractedText: output, additionalParts: imageParts)
    }

    static func preparedOpenRouterOCRPDF(
        _ attachment: DraftAttachment,
        profile: MessagePreparationProfile,
        totalPDFCount: Int,
        pdfOrdinal: Int,
        openRouterClient: OpenRouterOCRClient?,
        onStatusUpdate: @MainActor @Sendable (String) -> Void
    ) async throws -> PreparedPDFContent {
        guard let openRouterClient else { throw PDFProcessingError.openRouterOCRAPIKeyMissing }

        let selectedModel = await openRouterClient.selectedModel
        let includePageImages = profile.supportsVision
        let renderedPages = try PDFKitImageRenderer.renderAllPagesAsJPEG(from: attachment.fileURL)
        let totalPages = max(1, renderedPages.count)

        var pageMarkdown: [String] = []
        pageMarkdown.reserveCapacity(renderedPages.count)

        var imageParts: [ContentPart] = []
        var totalAttachedBytes = 0

        for rendered in renderedPages {
            try Task.checkCancellation()

            await onStatusUpdate(
                "OCR PDF \(pdfOrdinal)/\(max(1, totalPDFCount)) (OpenRouter \(selectedModel.name)): \(attachment.filename) — page \(rendered.pageIndex + 1)/\(totalPages)"
            )

            let raw = try await openRouterClient.ocrImage(
                rendered.data,
                mimeType: rendered.mimeType,
                prompt: OpenRouterOCRClient.Constants.defaultPrompt,
                timeoutSeconds: 120
            )

            let normalized = PDFProcessingUtilities.normalizedOpenRouterOCRMarkdown(raw)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                pageMarkdown.append(normalized)
            }

            if includePageImages,
               imageParts.count < AttachmentConstants.maxMistralOCRImagesToAttach {
                let nextTotal = totalAttachedBytes + rendered.data.count
                if nextTotal <= AttachmentConstants.maxMistralOCRTotalImageBytes {
                    totalAttachedBytes = nextTotal
                    imageParts.append(.image(ImageContent(mimeType: rendered.mimeType, data: rendered.data, url: nil)))
                }
            }
        }

        let combined = pageMarkdown
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !combined.isEmpty else {
            throw PDFProcessingError.noTextExtracted(filename: attachment.filename, method: "OpenRouter OCR")
        }

        var output = combined
        if includePageImages, !imageParts.isEmpty {
            let omitted = max(0, renderedPages.count - imageParts.count)
            output += "\n\n[Note: Attached \(imageParts.count) page image(s) for vision context.]"
            if omitted > 0 {
                output += "\n[Note: \(omitted) page image(s) omitted due to size limits.]"
            }
        }

        output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        output = "OpenRouter OCR (\(selectedModel.name) Markdown): \(attachment.filename)\n\n\(output)"
        output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.count > AttachmentConstants.maxPDFExtractedCharacters {
            let prefix = output.prefix(AttachmentConstants.maxPDFExtractedCharacters)
            output = "\(prefix)\n\n[Truncated]"
        }
        return PreparedPDFContent(extractedText: output, additionalParts: imageParts)
    }
}
