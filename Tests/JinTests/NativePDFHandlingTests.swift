import Foundation
import PDFKit
import XCTest
@testable import Jin

final class NativePDFHandlingTests: XCTestCase {
    func testVisionDoesNotImplyNativePDFForKimiHosts() {
        let kimiHosts: [(ProviderType, String)] = [
            (.deepinfra, "moonshotai/Kimi-K3"),
            (.together, "moonshotai/Kimi-K3"),
            (.fireworks, "accounts/fireworks/models/kimi-k3"),
            (.fireworks, "fireworks/kimi-k3"),
            (.kimiForCoding, "k3"),
            (.kimiForCoding, "kimi-for-coding"),
            (.opencodeGo, "kimi-k3"),
            (.baseten, "moonshotai/Kimi-K3"),
            (.modal, "moonshotai/Kimi-K3"),
            (.openrouter, "moonshotai/kimi-k3"),
            (.vercelAIGateway, "moonshotai/kimi-k3"),
            (.cloudflareAIGateway, "moonshotai/kimi-k3"),
        ]

        for (provider, modelID) in kimiHosts {
            XCTAssertFalse(
                JinModelSupport.supportsNativePDF(providerType: provider, modelID: modelID),
                "\(provider.rawValue) \(modelID) must not claim .nativePDF"
            )
            XCTAssertFalse(
                ChatModelCapabilitySupport.supportsNativePDF(
                    supportsMediaGenerationControl: false,
                    providerType: provider,
                    resolvedModelSettings: resolvedSettings(capabilities: [.vision, .nativePDF]),
                    lowerModelID: modelID.lowercased()
                ),
                "\(provider.rawValue) \(modelID) must stay on the native-PDF deny list"
            )
        }
    }

    func testPerplexityDoesNotClaimOrOfferNativePDF() {
        for id in ["sonar", "sonar-pro", "sonar-reasoning-pro", "sonar-deep-research", "sonar-reasoning"] {
            XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .perplexity, modelID: id), id)
            let info = ModelCatalog.modelInfo(for: id, provider: .perplexity)
            XCTAssertFalse(info.capabilities.contains(.nativePDF), id)
        }
        XCTAssertFalse(ProviderType.perplexity.supportsNativePDFUpload)
        XCTAssertFalse(
            ChatModelCapabilitySupport.supportsNativePDF(
                supportsMediaGenerationControl: false,
                providerType: .perplexity,
                resolvedModelSettings: resolvedSettings(capabilities: [.vision, .nativePDF]),
                lowerModelID: "sonar-pro"
            )
        )
    }

    func testPerplexityFileTranslationNeverEmitsPDFBytes() throws {
        let file = FileContent(
            mimeType: "application/pdf",
            filename: "report.pdf",
            data: Data("%PDF-1.7".utf8)
        )
        let parts = try translateUserContentPartsToOpenAIFormat([.file(file)])
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0]["type"] as? String, "text")
        XCTAssertNil(parts[0]["file"])
        XCTAssertNil(parts[0]["input_file"])
        let text = try XCTUnwrap(parts[0]["text"] as? String)
        XCTAssertTrue(text.contains("report.pdf"))
        XCTAssertFalse(text.contains("%PDF"))
    }

    func testGeminiAIStudio25CannotSendOrOfferNativePDFEvenIfSettingsClaimIt() {
        for id in ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-2.5"] {
            XCTAssertFalse(GeminiModelConstants.supportsNativePDF(id), id)
            XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .gemini, modelID: id), id)
            XCTAssertFalse(
                ChatModelCapabilitySupport.supportsNativePDF(
                    supportsMediaGenerationControl: false,
                    providerType: .gemini,
                    resolvedModelSettings: resolvedSettings(capabilities: [.vision, .nativePDF]),
                    lowerModelID: id
                ),
                id
            )
        }

        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .vertexai, modelID: "gemini-2.5-pro"))
        XCTAssertTrue(GeminiModelConstants.supportsVertexNativePDF("gemini-2.5-pro"))
        XCTAssertTrue(
            ChatModelCapabilitySupport.supportsNativePDF(
                supportsMediaGenerationControl: false,
                providerType: .vertexai,
                resolvedModelSettings: nil,
                lowerModelID: "gemini-2.5-pro"
            )
        )
    }

    func testPagesModeIsAvailableOnlyForVisionWithoutNativePDF() {
        XCTAssertTrue(
            ChatModelCapabilitySupport.isPDFProcessingModeAvailable(
                .pagesAsImages,
                supportsNativePDF: false,
                supportsVision: true,
                mistralOCRPluginEnabled: false,
                mineruOCRPluginEnabled: false,
                deepSeekOCRPluginEnabled: false,
                openRouterOCRPluginEnabled: false,
                firecrawlOCRPluginEnabled: false
            )
        )
        XCTAssertFalse(
            ChatModelCapabilitySupport.isPDFProcessingModeAvailable(
                .pagesAsImages,
                supportsNativePDF: true,
                supportsVision: true,
                mistralOCRPluginEnabled: false,
                mineruOCRPluginEnabled: false,
                deepSeekOCRPluginEnabled: false,
                openRouterOCRPluginEnabled: false,
                firecrawlOCRPluginEnabled: false
            )
        )
        XCTAssertFalse(
            ChatModelCapabilitySupport.isPDFProcessingModeAvailable(
                .pagesAsImages,
                supportsNativePDF: false,
                supportsVision: false,
                mistralOCRPluginEnabled: false,
                mineruOCRPluginEnabled: false,
                deepSeekOCRPluginEnabled: false,
                openRouterOCRPluginEnabled: false,
                firecrawlOCRPluginEnabled: false
            )
        )
    }

    func testResolvedModeFallsBackToPagesWhenVisionWithoutNative() {
        XCTAssertEqual(
            ChatModelCapabilitySupport.resolvedPDFProcessingMode(
                controls: GenerationControls(),
                supportsNativePDF: false,
                supportsVision: true,
                defaultPDFProcessingFallbackMode: .macOSExtract,
                mistralOCRPluginEnabled: false,
                mineruOCRPluginEnabled: false,
                deepSeekOCRPluginEnabled: false,
                openRouterOCRPluginEnabled: false,
                firecrawlOCRPluginEnabled: false
            ),
            .pagesAsImages
        )
        XCTAssertEqual(
            ChatModelCapabilitySupport.resolvedPDFProcessingMode(
                controls: GenerationControls(),
                supportsNativePDF: true,
                supportsVision: true,
                defaultPDFProcessingFallbackMode: .macOSExtract,
                mistralOCRPluginEnabled: false,
                mineruOCRPluginEnabled: false,
                deepSeekOCRPluginEnabled: false,
                openRouterOCRPluginEnabled: false,
                firecrawlOCRPluginEnabled: false
            ),
            .native
        )
        XCTAssertEqual(
            ChatModelCapabilitySupport.resolvedPDFProcessingMode(
                controls: GenerationControls(),
                supportsNativePDF: false,
                supportsVision: false,
                defaultPDFProcessingFallbackMode: .macOSExtract,
                mistralOCRPluginEnabled: false,
                mineruOCRPluginEnabled: false,
                deepSeekOCRPluginEnabled: false,
                openRouterOCRPluginEnabled: false,
                firecrawlOCRPluginEnabled: false
            ),
            .macOSExtract
        )
    }

    func testPreparedPagesAsImagesProducesImagesAndNoNativeExtract() async throws {
        let pdfURL = try writeFixturePDF()
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let attachment = DraftAttachment(
            id: UUID(),
            filename: "kimi.pdf",
            mimeType: "application/pdf",
            fileURL: pdfURL,
            extractedText: nil
        )
        let profile = ChatMessagePreparationSupport.MessagePreparationProfile(
            modelName: "Kimi K3",
            supportsVideoGenerationControl: false,
            supportsVideoInput: false,
            supportsMediaGenerationControl: false,
            supportsNativePDF: false,
            supportsVision: true,
            pdfProcessingMode: .pagesAsImages,
            firecrawlPDFParserMode: .ocr
        )

        let prepared = try await ChatMessagePreparationSupport.preparedContentForPDF(
            attachment,
            profile: profile,
            requestedMode: .pagesAsImages,
            totalPDFCount: 1,
            pdfOrdinal: 1,
            mistralClient: nil,
            mineruClient: nil,
            deepSeekClient: nil,
            openRouterClient: nil,
            firecrawlClient: nil,
            r2Uploader: nil,
            onStatusUpdate: { _ in }
        )

        let extracted = try XCTUnwrap(prepared.extractedText)
        XCTAssertTrue(extracted.contains("Pages as images"))
        XCTAssertFalse(extracted.isEmpty)
        XCTAssertEqual(prepared.additionalParts.count, 1)
        guard case .image(let image) = prepared.additionalParts[0] else {
            return XCTFail("Pages mode must emit image parts, not a native file send")
        }
        XCTAssertEqual(image.mimeType, "image/jpeg")
        XCTAssertFalse(image.data?.isEmpty ?? true)
    }

    func testBuildUserMessagePartsForPagesKeepsExtractNoteAndImages() async throws {
        let pdfURL = try writeFixturePDF()
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let profile = ChatMessagePreparationSupport.MessagePreparationProfile(
            modelName: "Kimi K3",
            supportsVideoGenerationControl: false,
            supportsVideoInput: false,
            supportsMediaGenerationControl: false,
            supportsNativePDF: false,
            supportsVision: true,
            pdfProcessingMode: .pagesAsImages,
            firecrawlPDFParserMode: .ocr
        )
        let pdf = DraftAttachment(
            id: UUID(),
            filename: "doc.pdf",
            mimeType: "application/pdf",
            fileURL: pdfURL,
            extractedText: nil
        )

        let parts = try await ChatMessagePreparationSupport.buildUserMessageParts(
            quoteContents: [],
            messageText: "Summarize",
            attachments: [pdf],
            remoteVideoURL: nil,
            profile: profile,
            preparedContentForPDF: { attachment, profile, mode, _, _, _, _, _, _, _, _ in
                XCTAssertEqual(mode, .pagesAsImages)
                return try await ChatMessagePreparationSupport.preparedContentForPDF(
                    attachment,
                    profile: profile,
                    requestedMode: mode,
                    totalPDFCount: 1,
                    pdfOrdinal: 1,
                    mistralClient: nil,
                    mineruClient: nil,
                    deepSeekClient: nil,
                    openRouterClient: nil,
                    firecrawlClient: nil,
                    r2Uploader: nil,
                    onStatusUpdate: { _ in }
                )
            }
        )

        XCTAssertEqual(parts.count, 3)
        guard case .file(let file) = parts[0] else {
            return XCTFail("Expected file note first")
        }
        XCTAssertEqual(file.filename, "doc.pdf")
        XCTAssertNotNil(file.extractedText)
        guard case .image = parts[1] else {
            return XCTFail("Expected rasterized page image")
        }
        guard case .text("Summarize") = parts[2] else {
            return XCTFail("Expected user text last")
        }
    }

    func testPagesModeWithoutVisionThrows() async throws {
        let pdfURL = try writeFixturePDF()
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let attachment = DraftAttachment(
            id: UUID(),
            filename: "doc.pdf",
            mimeType: "application/pdf",
            fileURL: pdfURL,
            extractedText: nil
        )
        let profile = ChatMessagePreparationSupport.MessagePreparationProfile(
            modelName: "Text Only",
            supportsVideoGenerationControl: false,
            supportsVideoInput: false,
            supportsMediaGenerationControl: false,
            supportsNativePDF: false,
            supportsVision: false,
            pdfProcessingMode: .pagesAsImages,
            firecrawlPDFParserMode: .ocr
        )

        do {
            _ = try await ChatMessagePreparationSupport.preparedContentForPDF(
                attachment,
                profile: profile,
                requestedMode: .pagesAsImages,
                totalPDFCount: 1,
                pdfOrdinal: 1,
                mistralClient: nil,
                mineruClient: nil,
                deepSeekClient: nil,
                openRouterClient: nil,
                firecrawlClient: nil,
                r2Uploader: nil,
                onStatusUpdate: { _ in }
            )
            XCTFail("Expected pagesAsImagesNotSupported")
        } catch let error as PDFProcessingError {
            XCTAssertEqual(
                error.localizedDescription,
                PDFProcessingError.pagesAsImagesNotSupported(modelName: "Text Only").localizedDescription
            )
        }
    }

    func testAnthropicCatalogHonorsUnsuffixedClaude4NativePDF() {
        for id in ["claude-opus-4", "claude-sonnet-4", "claude-haiku-4"] {
            XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .anthropic, modelID: id), id)
            XCTAssertTrue(
                ChatModelCapabilitySupport.supportsNativePDF(
                    supportsMediaGenerationControl: false,
                    providerType: .anthropic,
                    resolvedModelSettings: nil,
                    lowerModelID: id
                ),
                id
            )
        }
    }

    private func resolvedSettings(capabilities: ModelCapability) -> ResolvedModelSettings {
        ResolvedModelSettings(
            modelType: .chat,
            capabilities: capabilities,
            contextWindow: 128_000,
            maxOutputTokens: nil,
            reasoningConfig: nil,
            reasoningCanDisable: true,
            supportsWebSearch: false,
            requestShape: .openAICompatible,
            supportsOpenAIStyleReasoningEffort: false,
            supportsOpenAIStyleExtremeEffort: false
        )
    }

    private func writeFixturePDF() throws -> URL {
        let document = PDFDocument()
        let page = PDFPage()
        document.insert(page, at: 0)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jin-pages-\(UUID().uuidString).pdf")
        XCTAssertTrue(document.write(to: url))
        return url
    }
}
