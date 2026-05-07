import Foundation
import XCTest
@testable import Jin

final class ChatPDFPreparationSupportTests: XCTestCase {
    func testPDFPreparationClientsAreSkippedWhenDraftHasNoPDFs() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let clients = try ChatMessagePreparationSupport.makePDFPreparationClients(
            pdfCount: 0,
            requestedMode: .mistralOCR,
            defaults: defaults
        )

        XCTAssertNil(clients.mistralClient)
        XCTAssertNil(clients.mineruClient)
        XCTAssertNil(clients.deepSeekClient)
        XCTAssertNil(clients.openRouterClient)
        XCTAssertNil(clients.firecrawlClient)
        XCTAssertNil(clients.r2Uploader)
    }

    func testPDFPreparationClientsRequireSelectedOCRCredentialOnlyWhenPDFsExist() throws {
        let modesAndErrors: [(PDFProcessingMode, PDFProcessingError)] = [
            (.mistralOCR, .mistralAPIKeyMissing),
            (.mineruOCR, .mineruAPITokenMissing),
            (.deepSeekOCR, .deepInfraAPIKeyMissing),
            (.openRouterOCR, .openRouterOCRAPIKeyMissing),
            (.firecrawlOCR, .firecrawlAPIKeyMissing)
        ]

        for (mode, expectedError) in modesAndErrors {
            let (defaults, suiteName) = makeIsolatedDefaults()
            defer { defaults.removePersistentDomain(forName: suiteName) }

            XCTAssertThrowsError(
                try ChatMessagePreparationSupport.makePDFPreparationClients(
                    pdfCount: 1,
                    requestedMode: mode,
                    defaults: defaults
                )
            ) { error in
                XCTAssertEqual(error.localizedDescription, expectedError.localizedDescription)
            }
        }
    }

    func testPDFPreparationClientsBuildOnlyRequestedOCRClient() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(" openrouter-key ", forKey: AppPreferenceKeys.pluginOpenRouterOCRAPIKey)
        defaults.set("qwen/qwen3-vl-8b-instruct", forKey: AppPreferenceKeys.pluginOpenRouterOCRModelID)

        let clients = try ChatMessagePreparationSupport.makePDFPreparationClients(
            pdfCount: 1,
            requestedMode: .openRouterOCR,
            defaults: defaults
        )

        XCTAssertNil(clients.mistralClient)
        XCTAssertNil(clients.mineruClient)
        XCTAssertNil(clients.deepSeekClient)
        XCTAssertNotNil(clients.openRouterClient)
        XCTAssertNil(clients.firecrawlClient)
        XCTAssertNil(clients.r2Uploader)
    }

    func testBuildUserMessagePartsInvokesPDFPreparationWithPDFOrdinalAndAppendsAdditionalParts() async throws {
        let imageURL = URL(fileURLWithPath: "/tmp/photo.png")
        let pdfURL = URL(fileURLWithPath: "/tmp/report.pdf")
        let image = makeAttachment(filename: "photo.png", mimeType: "image/png", url: imageURL)
        let pdf = makeAttachment(filename: "report.pdf", mimeType: "application/pdf", url: pdfURL)
        let profile = makeProfile(pdfProcessingMode: .macOSExtract)
        var receivedPDFContext: (filename: String, mode: PDFProcessingMode, total: Int, ordinal: Int)?

        let parts = try await ChatMessagePreparationSupport.buildUserMessageParts(
            quoteContents: [],
            messageText: "Explain the attachments",
            attachments: [image, pdf],
            remoteVideoURL: nil,
            profile: profile,
            preparedContentForPDF: { attachment, _, mode, total, ordinal, mistral, mineru, deepSeek, openRouter, firecrawl, r2Uploader in
                receivedPDFContext = (attachment.filename, mode, total, ordinal)
                XCTAssertNil(mistral)
                XCTAssertNil(mineru)
                XCTAssertNil(deepSeek)
                XCTAssertNil(openRouter)
                XCTAssertNil(firecrawl)
                XCTAssertNil(r2Uploader)
                return ChatMessagePreparationSupport.PreparedPDFContent(
                    extractedText: "Prepared PDF text",
                    additionalParts: [.text("PDF sidecar")]
                )
            }
        )

        XCTAssertEqual(receivedPDFContext?.filename, "report.pdf")
        XCTAssertEqual(receivedPDFContext?.mode, .macOSExtract)
        XCTAssertEqual(receivedPDFContext?.total, 1)
        XCTAssertEqual(receivedPDFContext?.ordinal, 1)
        XCTAssertEqual(parts.count, 4)

        guard case .image(let imagePart) = parts[0] else {
            return XCTFail("Expected image part first")
        }
        XCTAssertEqual(imagePart.url, imageURL)

        guard case .file(let filePart) = parts[1] else {
            return XCTFail("Expected prepared PDF file part second")
        }
        XCTAssertEqual(filePart.filename, "report.pdf")
        XCTAssertEqual(filePart.extractedText, "Prepared PDF text")

        guard case .text("PDF sidecar") = parts[2] else {
            return XCTFail("Expected PDF additional part third")
        }
        guard case .text("Explain the attachments") = parts[3] else {
            return XCTFail("Expected message text last")
        }
    }
}

private func makeIsolatedDefaults() -> (UserDefaults, String) {
    let suiteName = "ChatPDFPreparationSupportTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
}

private func makeAttachment(filename: String, mimeType: String, url: URL) -> DraftAttachment {
    DraftAttachment(
        id: UUID(),
        filename: filename,
        mimeType: mimeType,
        fileURL: url,
        extractedText: nil
    )
}

private func makeProfile(pdfProcessingMode: PDFProcessingMode) -> ChatMessagePreparationSupport.MessagePreparationProfile {
    ChatMessagePreparationSupport.MessagePreparationProfile(
        threadID: UUID(),
        modelName: "Test Model",
        supportsVideoGenerationControl: false,
        supportsVideoInput: false,
        supportsMediaGenerationControl: false,
        supportsNativePDF: pdfProcessingMode == .native,
        supportsVision: false,
        pdfProcessingMode: pdfProcessingMode,
        firecrawlPDFParserMode: .ocr
    )
}
