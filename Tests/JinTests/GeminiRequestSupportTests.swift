import XCTest
@testable import Jin

final class GeminiRequestSupportTests: XCTestCase {
    func testGenerationConfigIncludesSamplingAndThinkingLevel() throws {
        let config = GeminiRequestSupport.generationConfig(
            controls: GenerationControls(
                temperature: 0.7,
                maxTokens: 1024,
                topP: 0.9,
                reasoning: ReasoningControls(enabled: true, effort: .medium)
            ),
            modelID: "gemini-3.1-pro-preview"
        )

        XCTAssertEqual(config["temperature"] as? Double, 0.7)
        XCTAssertEqual(config["maxOutputTokens"] as? Int, 1024)
        XCTAssertEqual(config["topP"] as? Double, 0.9)

        let thinkingConfig = try XCTUnwrap(config["thinkingConfig"] as? [String: Any])
        XCTAssertEqual(thinkingConfig["includeThoughts"] as? Bool, true)
        XCTAssertEqual(thinkingConfig["thinkingLevel"] as? String, "MEDIUM")
    }

    func testGenerationConfigSetsMediumThinkingLevelForGemini35Flash() throws {
        let config = GeminiRequestSupport.generationConfig(
            controls: GenerationControls(
                reasoning: ReasoningControls(enabled: true, effort: .medium)
            ),
            modelID: "gemini-3.5-flash"
        )

        let thinkingConfig = try XCTUnwrap(config["thinkingConfig"] as? [String: Any])
        XCTAssertEqual(thinkingConfig["includeThoughts"] as? Bool, true)
        XCTAssertEqual(thinkingConfig["thinkingLevel"] as? String, "MEDIUM")

        XCTAssertTrue(GeminiRequestSupport.supportsThinking("gemini-3.5-flash"))
        XCTAssertTrue(GeminiRequestSupport.supportsThinkingConfig("gemini-3.5-flash"))
        XCTAssertTrue(GeminiRequestSupport.supportsThinkingLevel("gemini-3.5-flash"))
    }

    func testGenerationConfigUsesMinimalThinkingLevelWhenGemini35FlashReasoningIsDisabled() throws {
        let config = GeminiRequestSupport.generationConfig(
            controls: GenerationControls(
                reasoning: ReasoningControls(enabled: false)
            ),
            modelID: "gemini-3.5-flash"
        )

        let thinkingConfig = try XCTUnwrap(config["thinkingConfig"] as? [String: Any])
        XCTAssertEqual(thinkingConfig["thinkingLevel"] as? String, "MINIMAL")
        XCTAssertNil(thinkingConfig["includeThoughts"])
    }

    func testGenerationConfigUsesLowThinkingLevelWhenGemini3ReasoningIsDisabled() throws {
        let config = GeminiRequestSupport.generationConfig(
            controls: GenerationControls(
                reasoning: ReasoningControls(enabled: false)
            ),
            modelID: "gemini-3-pro-preview"
        )

        let thinkingConfig = try XCTUnwrap(config["thinkingConfig"] as? [String: Any])
        XCTAssertEqual(thinkingConfig["thinkingLevel"] as? String, "LOW")
        XCTAssertNil(thinkingConfig["includeThoughts"])
    }

    func testGenerationConfigOmitsThinkingForProImageAndAddsImageConfig() throws {
        let config = GeminiRequestSupport.generationConfig(
            controls: GenerationControls(
                reasoning: ReasoningControls(enabled: true, effort: .high),
                imageGeneration: ImageGenerationControls(
                    responseMode: .imageOnly,
                    aspectRatio: .ratio16x9,
                    imageSize: .size512px,
                    seed: 1234
                )
            ),
            modelID: "gemini-3-pro-image-preview"
        )

        XCTAssertNil(config["thinkingConfig"])
        XCTAssertEqual(config["responseModalities"] as? [String], ["IMAGE"])
        XCTAssertEqual(config["seed"] as? Int, 1234)

        let imageConfig = try XCTUnwrap(config["imageConfig"] as? [String: Any])
        XCTAssertEqual(imageConfig["aspectRatio"] as? String, "16:9")
        XCTAssertNil(imageConfig["imageSize"], "Gemini 3 Pro Image does not support 512px output.")
    }

    func testGenerationConfigAllows512ImageSizeForGemini31FlashImage() throws {
        let config = GeminiRequestSupport.generationConfig(
            controls: GenerationControls(
                imageGeneration: ImageGenerationControls(imageSize: .size512px)
            ),
            modelID: "gemini-3.1-flash-image-preview"
        )

        let imageConfig = try XCTUnwrap(config["imageConfig"] as? [String: Any])
        XCTAssertEqual(imageConfig["imageSize"] as? String, "512px")
    }

    func testToolArrayBuildsNativeToolsAndFunctionDeclarations() throws {
        let tool = ToolDefinition(
            id: "lookup",
            name: "lookup",
            description: "Look up a thing.",
            parameters: ParameterSchema(
                properties: [
                    "q": PropertySchema(type: "string", description: "Query")
                ],
                required: ["q"]
            ),
            source: .builtin
        )

        let declarations = GeminiRequestSupport.functionDeclarations(from: [tool])
        let toolArray = GeminiRequestSupport.toolArray(
            controls: GenerationControls(
                webSearch: WebSearchControls(enabled: true),
                googleMaps: GoogleMapsControls(enabled: true, enableWidget: true),
                codeExecution: CodeExecutionControls(enabled: true)
            ),
            functionDeclarations: declarations,
            supportsWebSearch: true,
            supportsCodeExecution: true,
            supportsGoogleMaps: true,
            supportsFunctionCalling: true
        )

        XCTAssertEqual(toolArray.count, 4)
        XCTAssertNotNil(toolArray[0]["google_search"])
        XCTAssertNotNil(toolArray[1]["code_execution"])

        let googleMaps = try XCTUnwrap(toolArray[2]["googleMaps"] as? [String: Any])
        XCTAssertEqual(googleMaps["enableWidget"] as? Bool, true)

        let functionDeclarations = try XCTUnwrap(toolArray[3]["functionDeclarations"] as? [[String: Any]])
        XCTAssertEqual(functionDeclarations.first?["name"] as? String, "lookup")

        let parameters = try XCTUnwrap(functionDeclarations.first?["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["type"] as? String, "object")
        XCTAssertEqual(parameters["required"] as? [String], ["q"])
    }

    func testToolArrayOmitsFunctionDeclarationsWhenUnsupported() {
        let toolArray = GeminiRequestSupport.toolArray(
            controls: GenerationControls(webSearch: WebSearchControls(enabled: true)),
            functionDeclarations: [["name": "lookup"]],
            supportsWebSearch: false,
            supportsCodeExecution: false,
            supportsGoogleMaps: false,
            supportsFunctionCalling: false
        )

        XCTAssertTrue(toolArray.isEmpty)
    }

    func testToolConfigUsesMapsCoordinatesOnlyWhenSupported() throws {
        let config = GeminiRequestSupport.toolConfig(
            controls: GenerationControls(
                googleMaps: GoogleMapsControls(
                    enabled: true,
                    latitude: 37.7749,
                    longitude: -122.4194
                )
            ),
            supportsGoogleMaps: true
        )

        let retrievalConfig = try XCTUnwrap(config?["retrievalConfig"] as? [String: Any])
        let latLng = try XCTUnwrap(retrievalConfig["latLng"] as? [String: Any])
        XCTAssertEqual(latLng["latitude"] as? Double, 37.7749)
        XCTAssertEqual(latLng["longitude"] as? Double, -122.4194)

        XCTAssertNil(
            GeminiRequestSupport.toolConfig(
                controls: GenerationControls(
                    googleMaps: GoogleMapsControls(enabled: true, latitude: 37.7749, longitude: -122.4194)
                ),
                supportsGoogleMaps: false
            )
        )
    }

    func testSystemInstructionAndCachedContentHelpersNormalizeInputs() {
        let systemInstruction = GeminiRequestSupport.systemInstructionText(from: [
            Message(role: .system, content: [.text(" First. ")]),
            Message(role: .user, content: [.text("Ignore")]),
            Message(role: .system, content: [.text("Second.")])
        ])
        XCTAssertEqual(systemInstruction, "First. Second.")

        let explicitCache = GeminiRequestSupport.explicitCachedContentName(
            from: GenerationControls(
                contextCache: ContextCacheControls(mode: .explicit, cachedContentName: " cachedContents/cache-123 ")
            )
        )
        XCTAssertEqual(explicitCache, "cachedContents/cache-123")

        XCTAssertEqual(
            GeminiRequestSupport.normalizedCachedContentName(" cache-123 "),
            "cachedContents/cache-123"
        )
        XCTAssertEqual(
            GeminiRequestSupport.normalizedCachedContentName(" cachedContents/cache-123 "),
            "cachedContents/cache-123"
        )
        XCTAssertEqual(
            GeminiRequestSupport.modelIDForPath(" models/gemini-3-pro "),
            "gemini-3-pro"
        )
        XCTAssertNil(
            GeminiRequestSupport.systemInstructionText(from: [
                Message(role: .system, content: [.text(" \n\t ")])
            ])
        )
    }
}
