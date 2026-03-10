import Foundation
import XCTest
@testable import Jin

final class AdapterUtilitiesTests: XCTestCase {
    func testValidatedURLAcceptsSupportedAbsoluteSchemes() throws {
        let httpsURL = try validatedURL("https://api.example.com/v1")
        XCTAssertEqual(httpsURL.scheme, "https")
        XCTAssertEqual(httpsURL.host, "api.example.com")

        let wssURL = try validatedURL("wss://api.example.com/v1")
        XCTAssertEqual(wssURL.scheme, "wss")
        XCTAssertEqual(wssURL.host, "api.example.com")
    }

    func testValidatedURLRejectsRelativeEndpoint() {
        XCTAssertThrowsError(try validatedURL("api.example.com/v1")) { error in
            guard case .invalidRequest(let message) = error as? LLMError else {
                return XCTFail("Expected LLMError.invalidRequest")
            }
            XCTAssertTrue(message.contains("must be absolute"))
        }
    }

    func testValidatedURLRejectsUnsupportedScheme() {
        XCTAssertThrowsError(try validatedURL("ftp://api.example.com/v1")) { error in
            guard case .invalidRequest(let message) = error as? LLMError else {
                return XCTFail("Expected LLMError.invalidRequest")
            }
            XCTAssertTrue(message.contains("Invalid URL scheme"))
        }
    }

    func testSplitContentPartsKeepsThinkingUnseparatedWhenVisibleUsesSeparator() {
        let parts: [ContentPart] = [
            .text("visible-a"),
            .text("visible-b"),
            .thinking(ThinkingBlock(text: "think-a")),
            .thinking(ThinkingBlock(text: "think-b"))
        ]

        let split = splitContentParts(parts, separator: "\n")
        XCTAssertEqual(split.visible, "visible-a\nvisible-b")
        XCTAssertEqual(split.thinking, "think-athink-b")
    }

    func testFindConfiguredModelMatchesExactAndCaseInsensitive() {
        let provider = ProviderConfig(
            id: "p1",
            name: "Provider",
            type: .openaiCompatible,
            models: [
                ModelInfo(
                    id: "gpt-4o",
                    name: "GPT-4o",
                    capabilities: [.streaming],
                    contextWindow: 128_000
                )
            ]
        )

        XCTAssertNotNil(findConfiguredModel(in: provider, for: "gpt-4o"))
        // Case-insensitive fallback: "GPT-4O" matches "gpt-4o"
        XCTAssertNotNil(findConfiguredModel(in: provider, for: "GPT-4O"))
        // No match for completely different ID
        XCTAssertNil(findConfiguredModel(in: provider, for: "gpt-5"))
    }

    func testFindConfiguredModelReturnsConfiguredMetadataOverRegistryDefaults() {
        let provider = ProviderConfig(
            id: "p1",
            name: "Provider",
            type: .openai,
            models: [
                ModelInfo(
                    id: "gpt-4o",
                    name: "Custom GPT-4o",
                    capabilities: [.audio],
                    contextWindow: 4_096
                )
            ]
        )

        let configured = findConfiguredModel(in: provider, for: "gpt-4o")
        XCTAssertEqual(configured?.contextWindow, 4_096)
        XCTAssertEqual(configured?.capabilities, [.audio])
    }

    func testModelSupportsWebSearchUsesConfiguredOverrideWhenModelExists() {
        let provider = ProviderConfig(
            id: "p1",
            name: "Provider",
            type: .openai,
            models: [
                ModelInfo(
                    id: "gpt-4o",
                    name: "GPT-4o",
                    capabilities: [.streaming, .toolCalling, .vision],
                    contextWindow: 128_000,
                    overrides: ModelOverrides(webSearchSupported: false)
                )
            ]
        )

        XCTAssertFalse(modelSupportsWebSearch(providerConfig: provider, modelID: "gpt-4o"))
    }

    func testModelSupportsWebSearchFallsBackToRegistryForLegacyIDOnlyScenario() {
        let provider = ProviderConfig(
            id: "p1",
            name: "Provider",
            type: .openai,
            models: []
        )

        XCTAssertTrue(modelSupportsWebSearch(providerConfig: provider, modelID: "gpt-4o"))
    }

    func testModelSupportsReasoningUsesCatalogMetadataForKnownOpenAIModels() {
        let provider = ProviderConfig(
            id: "p1",
            name: "Provider",
            type: .openai,
            models: []
        )

        XCTAssertTrue(modelSupportsReasoning(providerConfig: provider, modelID: "gpt-5.2"))
        XCTAssertFalse(modelSupportsReasoning(providerConfig: provider, modelID: "gpt-5.3-chat-latest"))
    }

    func testOpenAIResponsesSamplingParametersSupportForGPT5Families() {
        XCTAssertTrue(supportsOpenAIResponsesSamplingParameters(modelID: "gpt-4o", reasoningEnabled: false))

        XCTAssertTrue(supportsOpenAIResponsesSamplingParameters(modelID: "gpt-5.2", reasoningEnabled: false))
        XCTAssertTrue(supportsOpenAIResponsesSamplingParameters(modelID: "openai/gpt-5.2-2025-12-11", reasoningEnabled: false))
        XCTAssertFalse(supportsOpenAIResponsesSamplingParameters(modelID: "gpt-5.2", reasoningEnabled: true))

        XCTAssertFalse(supportsOpenAIResponsesSamplingParameters(modelID: "gpt-5.3-chat-latest", reasoningEnabled: false))
        XCTAssertFalse(supportsOpenAIResponsesSamplingParameters(modelID: "gpt-5.3-codex", reasoningEnabled: false))
        XCTAssertFalse(supportsOpenAIResponsesSamplingParameters(modelID: "gpt-5", reasoningEnabled: false))
    }

    func testMakeAuthorizedJSONRequestWithoutBodyOmitsContentType() throws {
        let request = try makeAuthorizedJSONRequest(
            url: URL(string: "https://example.com/request")!,
            method: "POST",
            apiKey: "test-key"
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertNil(request.httpBody)
    }

    func testNormalizedMIMETypeTrimsAndLowercasesForSetMembership() {
        let normalized = normalizedMIMEType(" Application/PDF \n")
        XCTAssertEqual(normalized, "application/pdf")
        XCTAssertTrue(openAISupportedFileMIMETypes.contains(normalized))
    }

    // MARK: - resolveFileData

    func testResolveFileDataThrowsForMissingFile() {
        let missingURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("jin-test-missing-\(UUID().uuidString).png")

        XCTAssertThrowsError(try resolveFileData(from: missingURL)) { error in
            guard case .invalidRequest(let message) = error as? LLMError else {
                return XCTFail("Expected LLMError.invalidRequest, got \(error)")
            }
            XCTAssertTrue(message.contains("Failed to read attachment"))
            XCTAssertTrue(message.contains(missingURL.lastPathComponent))
        }
    }

    func testResolveFileDataSucceedsForReadableFile() throws {
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("jin-test-readable-\(UUID().uuidString).txt")
        let content = Data("hello".utf8)
        try content.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let data = try resolveFileData(from: tmpURL)
        XCTAssertEqual(data, content)
    }

    // MARK: - Attachment translation throws (not silent drop)

    func testImageToURLStringThrowsForUnreadableLocalFile() {
        let missingURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("jin-test-missing-\(UUID().uuidString).jpg")
        let image = ImageContent(mimeType: "image/jpeg", data: nil, url: missingURL)

        XCTAssertThrowsError(try imageToURLString(image)) { error in
            guard case .invalidRequest(let message) = error as? LLMError else {
                return XCTFail("Expected LLMError.invalidRequest, got \(error)")
            }
            XCTAssertTrue(message.contains("Failed to read attachment"))
        }
    }

    func testTranslateUserContentPartsThrowsForUnreadableImageAttachment() {
        let missingURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("jin-test-missing-\(UUID().uuidString).png")
        let parts: [ContentPart] = [
            .text("describe this image"),
            .image(ImageContent(mimeType: "image/png", data: nil, url: missingURL))
        ]

        XCTAssertThrowsError(try translateUserContentPartsToOpenAIFormat(parts)) { error in
            guard case .invalidRequest(let message) = error as? LLMError else {
                return XCTFail("Expected LLMError.invalidRequest, got \(error)")
            }
            XCTAssertTrue(message.contains("Failed to read attachment"))
        }
    }
}
