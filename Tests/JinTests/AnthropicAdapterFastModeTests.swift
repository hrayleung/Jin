import Foundation
import XCTest
@testable import Jin

final class AnthropicAdapterFastModeTests: XCTestCase {

    // MARK: - applySpeedConfig

    func testApplySpeedConfigSetsFastOnOpus47WhenEnabled() {
        var body: [String: Any] = [:]
        let controls = GenerationControls(anthropicSpeed: .fast)

        AnthropicRequestBodySupport.applySpeedConfig(
            to: &body,
            controls: controls,
            providerType: .anthropic,
            modelID: "claude-opus-4-7"
        )

        XCTAssertEqual(body["speed"] as? String, "fast")
    }

    func testApplySpeedConfigSetsFastOnOpus46WhenEnabled() {
        var body: [String: Any] = [:]
        let controls = GenerationControls(anthropicSpeed: .fast)

        AnthropicRequestBodySupport.applySpeedConfig(
            to: &body,
            controls: controls,
            providerType: .anthropic,
            modelID: "claude-opus-4-6"
        )

        XCTAssertEqual(body["speed"] as? String, "fast")
    }

    func testApplySpeedConfigOmitsSpeedOnUnsupportedModel() {
        var body: [String: Any] = [:]
        let controls = GenerationControls(anthropicSpeed: .fast)

        AnthropicRequestBodySupport.applySpeedConfig(
            to: &body,
            controls: controls,
            providerType: .anthropic,
            modelID: "claude-sonnet-4-6"
        )

        XCTAssertNil(body["speed"])
    }

    func testApplySpeedConfigOmitsSpeedWhenDisabled() {
        var body: [String: Any] = [:]
        let controls = GenerationControls(anthropicSpeed: nil)

        AnthropicRequestBodySupport.applySpeedConfig(
            to: &body,
            controls: controls,
            providerType: .anthropic,
            modelID: "claude-opus-4-7"
        )

        XCTAssertNil(body["speed"])
    }

    func testApplySpeedConfigSkipsNonDirectAnthropicProvider() {
        var body: [String: Any] = [:]
        let controls = GenerationControls(anthropicSpeed: .fast)

        AnthropicRequestBodySupport.applySpeedConfig(
            to: &body,
            controls: controls,
            providerType: .mimoTokenPlanAnthropic,
            modelID: "claude-opus-4-7"
        )

        XCTAssertNil(body["speed"])
    }

    // MARK: - Beta header merging

    func testBetaHeaderIncludesFastModeWhenEnabled() {
        let header = AnthropicRequestPreparationSupport.betaHeader(
            from: GenerationControls(),
            messages: [],
            codeExecutionEnabled: false,
            fastModeEnabled: true
        )

        XCTAssertEqual(header, "fast-mode-2026-02-01")
    }

    func testBetaHeaderMergesFastModeWithFilesAPI() throws {
        let messages = [
            Message(
                role: .user,
                content: [
                    .file(FileContent(
                        mimeType: "application/pdf",
                        filename: "paper.pdf",
                        data: Data([0x25, 0x50, 0x44, 0x46])
                    ))
                ]
            )
        ]

        let header = try XCTUnwrap(
            AnthropicRequestPreparationSupport.betaHeader(
                from: GenerationControls(),
                messages: messages,
                codeExecutionEnabled: false,
                fastModeEnabled: true
            )
        )

        let parts = header
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        XCTAssertTrue(parts.contains("files-api-2025-04-14"))
        XCTAssertTrue(parts.contains("fast-mode-2026-02-01"))
        XCTAssertEqual(parts.count, 2)
    }

    func testBetaHeaderOmitsFastModeWhenDisabled() {
        let header = AnthropicRequestPreparationSupport.betaHeader(
            from: GenerationControls(),
            messages: [],
            codeExecutionEnabled: false,
            fastModeEnabled: false
        )

        XCTAssertNil(header)
    }

    // MARK: - Usage parsing

    func testUsageInfoDecodesSpeedField() throws {
        let json = """
        {
          "type": "message_delta",
          "usage": {
            "input_tokens": 12,
            "output_tokens": 34,
            "speed": "fast"
          }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let event = try decoder.decode(AnthropicStreamEvent.self, from: json)

        XCTAssertEqual(event.usage?.speed, "fast")
    }

    func testUsageAccumulatorMergesSpeed() {
        var accumulator = AnthropicUsageAccumulator()
        let usage = AnthropicStreamEvent.UsageInfo(
            inputTokens: 1,
            outputTokens: 2,
            cacheCreationInputTokens: nil,
            cacheReadInputTokens: nil,
            serviceTier: nil,
            inferenceGeo: nil,
            speed: "fast"
        )

        accumulator.merge(usage)

        XCTAssertEqual(accumulator.speed, "fast")
    }

    // MARK: - Model gating

    func testSupportsFastModeOnOpus47AndOpus46() {
        XCTAssertTrue(AnthropicModelLimits.supportsFastMode(for: "claude-opus-4-7"))
        XCTAssertTrue(AnthropicModelLimits.supportsFastMode(for: "claude-opus-4-6"))
    }

    func testSupportsFastModeRejectsOtherModels() {
        XCTAssertFalse(AnthropicModelLimits.supportsFastMode(for: "claude-sonnet-4-6"))
        XCTAssertFalse(AnthropicModelLimits.supportsFastMode(for: "claude-opus-4-5"))
        XCTAssertFalse(AnthropicModelLimits.supportsFastMode(for: "claude-haiku-4-5"))
        XCTAssertFalse(AnthropicModelLimits.supportsFastMode(for: "claude-opus-4"))
    }

    func testSupportsFastModeRejectsDateSuffixedAndCustomOpusVariants() {
        // Anthropic documents fast mode for the exact model IDs only — refuse
        // hypothetical date snapshots or custom suffixes so we never send
        // `speed: "fast"` for a model the API would reject.
        XCTAssertFalse(AnthropicModelLimits.supportsFastMode(for: "claude-opus-4-7-20260128"))
        XCTAssertFalse(AnthropicModelLimits.supportsFastMode(for: "claude-opus-4-6-20260101"))
        XCTAssertFalse(AnthropicModelLimits.supportsFastMode(for: "claude-opus-4-7-custom"))
        XCTAssertFalse(AnthropicModelLimits.supportsFastMode(for: "claude-opus-4-7-thinking"))
    }

    // MARK: - Error parsing for fast mode

    func test429WithFastModeHeadersFlagsExhaustedAndSurfacesProviderMessage() throws {
        let body = Data(#"""
        {"type":"error","error":{"type":"rate_limit_error","message":"Fast mode rate limit reached."}}
        """#.utf8)
        let headers: [AnyHashable: Any] = [
            "Retry-After": "7",
            "anthropic-fast-input-tokens-remaining": "0",
            "anthropic-fast-input-tokens-reset": "2026-05-14T12:00:00Z"
        ]

        let error = try NetworkManager().parseHTTPError(statusCode: 429, data: body, headers: headers)

        guard case let .rateLimitExceeded(retryAfter, providerMessage, fastModeExhausted) = error else {
            XCTFail("Expected .rateLimitExceeded, got \(error)")
            return
        }
        XCTAssertEqual(retryAfter, 7)
        XCTAssertEqual(providerMessage, "Fast mode rate limit reached.")
        XCTAssertTrue(fastModeExhausted)

        let description = try XCTUnwrap(error.errorDescription)
        XCTAssertTrue(description.contains("Fast mode rate limit reached."))
        XCTAssertTrue(description.contains("Fast mode capacity reached"))
    }

    func test429WithoutFastModeHeadersDoesNotFlagExhausted() throws {
        let body = Data(#"{"error":{"message":"Slow down"}}"#.utf8)
        let headers: [AnyHashable: Any] = ["Retry-After": "5"]

        let error = try NetworkManager().parseHTTPError(statusCode: 429, data: body, headers: headers)

        guard case let .rateLimitExceeded(_, _, fastModeExhausted) = error else {
            XCTFail("Expected .rateLimitExceeded, got \(error)")
            return
        }
        XCTAssertFalse(fastModeExhausted)

        let description = try XCTUnwrap(error.errorDescription)
        XCTAssertFalse(description.contains("Fast mode capacity reached"))
    }

    func test400WithAnthropicErrorBodySurfacesMessage() throws {
        let body = Data(#"""
        {"type":"error","error":{"type":"invalid_request_error","message":"Fast mode is not enabled for this organization."}}
        """#.utf8)

        let error = try NetworkManager().parseHTTPError(statusCode: 400, data: body, headers: [:])

        guard case let .providerError(code, message) = error else {
            XCTFail("Expected .providerError, got \(error)")
            return
        }
        XCTAssertEqual(code, "400")
        XCTAssertEqual(message, "Fast mode is not enabled for this organization.")
    }
}
