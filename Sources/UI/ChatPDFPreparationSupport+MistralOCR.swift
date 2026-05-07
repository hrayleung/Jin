import Collections
import Foundation

extension ChatMessagePreparationSupport {
    static func preparedMistralOCRPDF(
        _ attachment: DraftAttachment,
        profile: MessagePreparationProfile,
        totalPDFCount: Int,
        pdfOrdinal: Int,
        mistralClient: MistralOCRClient?,
        onStatusUpdate: @MainActor @Sendable (String) -> Void
    ) async throws -> PreparedPDFContent {
        guard let mistralClient else { throw PDFProcessingError.mistralAPIKeyMissing }

        await onStatusUpdate("OCR PDF \(pdfOrdinal)/\(max(1, totalPDFCount)) (Mistral): \(attachment.filename)")

        guard let data = try? Data(contentsOf: attachment.fileURL) else {
            throw PDFProcessingError.fileReadFailed(filename: attachment.filename)
        }

        let includeImageBase64 = profile.supportsVision
        let response = try await mistralClient.ocrPDF(data, includeImageBase64: includeImageBase64)
        let pages = response.pages
            .sorted { $0.index < $1.index }
        var combinedMarkdown = pages
            .map(\.markdown)
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var tablesByID: [String: String] = [:]
        for page in pages {
            for table in page.tables ?? [] {
                let id = table.id.trimmingCharacters(in: .whitespacesAndNewlines)
                let content = table.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !id.isEmpty, !content.isEmpty else { continue }
                tablesByID[id] = content
                tablesByID[(id as NSString).lastPathComponent] = content
            }
        }

        if !tablesByID.isEmpty {
            combinedMarkdown = MistralOCRMarkdown.replacingTableLinks(from: combinedMarkdown) { id in
                guard !id.isEmpty else { return "" }
                if let content = tablesByID[id] { return content }
                return "[\(id)](\(id))"
            }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !combinedMarkdown.isEmpty else {
            throw PDFProcessingError.noTextExtracted(filename: attachment.filename, method: "Mistral OCR")
        }

        let textOnlyMarkdown = MistralOCRMarkdown.removingImageMarkdown(from: combinedMarkdown)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasText = !textOnlyMarkdown.isEmpty

        var imageParts: [ContentPart] = []
        var attachedImageIDs = Set<String>()
        var totalAttachedImageBytes = 0

        if includeImageBase64 {
            var base64ByID: OrderedDictionary<String, String> = [:]
            var idsInPageOrder = OrderedSet<String>()

            for page in pages {
                for image in page.images ?? [] {
                    let id = image.id
                    idsInPageOrder.append(id)
                    if let base64 = image.imageBase64, !base64.isEmpty {
                        base64ByID[id] = base64
                    }
                }
            }

            let referencedIDs = MistralOCRMarkdown.referencedImageIDs(in: combinedMarkdown)
            var orderedIDs = OrderedSet<String>()
            orderedIDs.reserveCapacity(max(referencedIDs.count, idsInPageOrder.count))
            for id in referencedIDs {
                orderedIDs.append(id)
            }
            for id in idsInPageOrder {
                orderedIDs.append(id)
            }

            for id in orderedIDs {
                guard imageParts.count < AttachmentConstants.maxMistralOCRImagesToAttach else { break }
                guard let base64 = base64ByID[id] else { continue }
                guard let decoded = PDFProcessingUtilities.decodeMistralOCRImageBase64(base64, imageID: id) else { continue }
                guard let decodedData = decoded.data else { continue }

                let nextTotal = totalAttachedImageBytes + decodedData.count
                guard nextTotal <= AttachmentConstants.maxMistralOCRTotalImageBytes else { break }
                totalAttachedImageBytes = nextTotal

                attachedImageIDs.insert(id)
                imageParts.append(.image(decoded))
            }
        }

        let extractedText: String
        if includeImageBase64 {
            let replaced = MistralOCRMarkdown.replacingImageMarkdown(from: combinedMarkdown) { id in
                let label = attachedImageIDs.contains(id) ? "Image attached" : "Image omitted"
                if id.isEmpty { return "[\(label)]" }
                return "[\(label): \(id)]"
            }
            extractedText = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            extractedText = textOnlyMarkdown
        }

        if !hasText, imageParts.isEmpty {
            throw PDFProcessingError.noTextExtracted(filename: attachment.filename, method: "Mistral OCR (image-only — requires vision)")
        }

        var output = extractedText
        if !hasText, !imageParts.isEmpty {
            output = "Mistral OCR extracted images (no text) from this PDF. See attached images."
        }

        let extractedImageCount = pages.reduce(0) { $0 + (($1.images ?? []).count) }
        let omittedCount = max(0, extractedImageCount - attachedImageIDs.count)
        if includeImageBase64, omittedCount > 0 {
            output += "\n\n[Note: \(omittedCount) extracted image(s) omitted due to size limits.]"
        }

        output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        output = "Mistral OCR (Markdown): \(attachment.filename)\n\n\(output)"
        output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.count > AttachmentConstants.maxPDFExtractedCharacters {
            let prefix = output.prefix(AttachmentConstants.maxPDFExtractedCharacters)
            output = "\(prefix)\n\n[Truncated]"
        }
        return PreparedPDFContent(extractedText: output, additionalParts: imageParts)
    }
}
