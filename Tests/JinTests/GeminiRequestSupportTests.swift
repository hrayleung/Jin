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

    func testGenerationConfigOmitsCustomSamplingForGemini36FlashAnd35FlashLite() {
        for modelID in ["gemini-3.7-flash", "gemini-3.6-flash", "gemini-3.5-flash-lite"] {
            let config = GeminiRequestSupport.generationConfig(
                controls: GenerationControls(
                    temperature: 0.2,
                    maxTokens: 2048,
                    topP: 0.5,
                    reasoning: ReasoningControls(enabled: true, effort: .high)
                ),
                modelID: modelID
            )

            XCTAssertNil(config["temperature"], modelID)
            XCTAssertNil(config["topP"], modelID)
            XCTAssertEqual(config["maxOutputTokens"] as? Int, 2048, modelID)
            XCTAssertFalse(GeminiModelConstants.supportsCustomSamplingParameters(modelID), modelID)
        }
    }

    func testSupportsCustomSamplingCanonicalizesPathQualifiedModelIDs() {
        XCTAssertFalse(
            GeminiModelConstants.supportsCustomSamplingParameters("models/gemini-3.6-flash")
        )
        XCTAssertFalse(
            GeminiModelConstants.supportsCustomSamplingParameters(
                "publishers/google/models/gemini-3.5-flash-lite"
            )
        )
        XCTAssertTrue(
            GeminiModelConstants.supportsCustomSamplingParameters("models/gemini-3.5-flash")
        )

        let config = GeminiRequestSupport.generationConfig(
            controls: GenerationControls(temperature: 0.3, topP: 0.4),
            modelID: "models/gemini-3.6-flash"
        )
        XCTAssertNil(config["temperature"])
        XCTAssertNil(config["topP"])
    }

    func testGenerationConfigNeverSendsMinimalThinkingLevelForGemini37Flash() throws {
        // Docs (2026-08-13): thinking_level="MINIMAL" is an API validation error on 3.7 Flash,
        // so a carried-over `.minimal`/`.none` selection must fold down to LOW on the wire.
        for effort in [ReasoningEffort.minimal, .none] {
            let config = GeminiRequestSupport.generationConfig(
                controls: GenerationControls(
                    reasoning: ReasoningControls(enabled: true, effort: effort)
                ),
                modelID: "gemini-3.7-flash"
            )

            let thinkingConfig = try XCTUnwrap(config["thinkingConfig"] as? [String: Any])
            XCTAssertEqual(thinkingConfig["thinkingLevel"] as? String, "LOW", "\(effort)")
        }

        // Reasoning switched off still has to pick a level the model accepts.
        let disabled = GeminiRequestSupport.generationConfig(
            controls: GenerationControls(reasoning: ReasoningControls(enabled: false)),
            modelID: "gemini-3.7-flash"
        )
        let disabledThinking = try XCTUnwrap(disabled["thinkingConfig"] as? [String: Any])
        XCTAssertEqual(disabledThinking["thinkingLevel"] as? String, "LOW")
    }

    func testGenerationConfigSetsMediumThinkingLevelForGemini37Flash() throws {
        let config = GeminiRequestSupport.generationConfig(
            controls: GenerationControls(
                reasoning: ReasoningControls(enabled: true, effort: .medium)
            ),
            modelID: "gemini-3.7-flash"
        )

        let thinkingConfig = try XCTUnwrap(config["thinkingConfig"] as? [String: Any])
        XCTAssertEqual(thinkingConfig["includeThoughts"] as? Bool, true)
        XCTAssertEqual(thinkingConfig["thinkingLevel"] as? String, "MEDIUM")
    }

    func testGenerationConfigSetsMediumThinkingLevelForGemini36Flash() throws {
        let config = GeminiRequestSupport.generationConfig(
            controls: GenerationControls(
                reasoning: ReasoningControls(enabled: true, effort: .medium)
            ),
            modelID: "gemini-3.6-flash"
        )

        let thinkingConfig = try XCTUnwrap(config["thinkingConfig"] as? [String: Any])
        XCTAssertEqual(thinkingConfig["thinkingLevel"] as? String, "MEDIUM")
    }

    func testGenerationConfigSetsMinimalThinkingLevelForGemini35FlashLite() throws {
        let config = GeminiRequestSupport.generationConfig(
            controls: GenerationControls(
                reasoning: ReasoningControls(enabled: true, effort: .minimal)
            ),
            modelID: "gemini-3.5-flash-lite"
        )

        let thinkingConfig = try XCTUnwrap(config["thinkingConfig"] as? [String: Any])
        XCTAssertEqual(thinkingConfig["thinkingLevel"] as? String, "MINIMAL")
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

        let mixedToolConfig = try XCTUnwrap(
            GeminiRequestSupport.toolConfig(
                controls: GenerationControls(
                    webSearch: WebSearchControls(enabled: true),
                    googleMaps: GoogleMapsControls(enabled: true, enableWidget: true),
                    codeExecution: CodeExecutionControls(enabled: true)
                ),
                tools: toolArray,
                supportsGoogleMaps: true
            )
        )
        XCTAssertEqual(mixedToolConfig["includeServerSideToolInvocations"] as? Bool, true)
        XCTAssertNil(mixedToolConfig["retrievalConfig"])
    }

    func testToolConfigSetsIncludeServerSideToolInvocationsOnlyWhenMixingBuiltInAndFunctionCalling() {
        let functionTools: [[String: Any]] = [
            ["functionDeclarations": [["name": "lookup"]]]
        ]
        let codeExecutionTools: [[String: Any]] = [
            ["code_execution": [:]]
        ]
        let mixedTools: [[String: Any]] = [
            ["code_execution": [:]],
            ["functionDeclarations": [["name": "lookup"]]]
        ]
        let vertexMixedTools: [[String: Any]] = [
            ["googleSearch": [:]],
            ["functionDeclarations": [["name": "lookup"]]]
        ]

        XCTAssertTrue(GeminiRequestSupport.shouldIncludeServerSideToolInvocations(in: mixedTools))
        XCTAssertTrue(GeminiRequestSupport.shouldIncludeServerSideToolInvocations(in: vertexMixedTools))
        XCTAssertFalse(GeminiRequestSupport.shouldIncludeServerSideToolInvocations(in: functionTools))
        XCTAssertFalse(GeminiRequestSupport.shouldIncludeServerSideToolInvocations(in: codeExecutionTools))
        XCTAssertFalse(GeminiRequestSupport.shouldIncludeServerSideToolInvocations(in: []))

        let mixedConfig = GeminiRequestSupport.toolConfig(
            controls: GenerationControls(),
            tools: mixedTools,
            supportsGoogleMaps: false
        )
        XCTAssertEqual(mixedConfig?["includeServerSideToolInvocations"] as? Bool, true)

        XCTAssertNil(
            GeminiRequestSupport.toolConfig(
                controls: GenerationControls(),
                tools: functionTools,
                supportsGoogleMaps: false
            )
        )
        XCTAssertNil(
            GeminiRequestSupport.toolConfig(
                controls: GenerationControls(),
                tools: codeExecutionTools,
                supportsGoogleMaps: false
            )
        )
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
        let mapsControls = GenerationControls(
            googleMaps: GoogleMapsControls(
                enabled: true,
                latitude: GoogleMapsCoordinateFixture.latitude,
                longitude: GoogleMapsCoordinateFixture.longitude
            )
        )
        let config = GeminiRequestSupport.toolConfig(
            controls: mapsControls,
            tools: [["googleMaps": [:]]],
            supportsGoogleMaps: true
        )

        let retrievalConfig = try XCTUnwrap(config?["retrievalConfig"] as? [String: Any])
        let latLng = try XCTUnwrap(retrievalConfig["latLng"] as? [String: Any])
        XCTAssertEqual(latLng["latitude"] as? Double, GoogleMapsCoordinateFixture.latitude)
        XCTAssertEqual(latLng["longitude"] as? Double, GoogleMapsCoordinateFixture.longitude)
        XCTAssertNil(config?["includeServerSideToolInvocations"])

        let mixedConfig = try XCTUnwrap(
            GeminiRequestSupport.toolConfig(
                controls: mapsControls,
                tools: [
                    ["googleMaps": [:]],
                    ["functionDeclarations": [["name": "lookup"]]]
                ],
                supportsGoogleMaps: true
            )
        )
        XCTAssertEqual(mixedConfig["includeServerSideToolInvocations"] as? Bool, true)
        XCTAssertNotNil(mixedConfig["retrievalConfig"])

        XCTAssertNil(
            GeminiRequestSupport.toolConfig(
                controls: mapsControls,
                tools: [["googleMaps": [:]]],
                supportsGoogleMaps: false
            )
        )
    }

    func testSystemInstructionAddsGoogleMapsLocationContextWhenSupported() throws {
        let systemInstruction = try XCTUnwrap(GeminiRequestSupport.systemInstructionText(
            from: [Message(role: .system, content: [.text("Be concise.")])],
            controls: GenerationControls(
                googleMaps: GoogleMapsControls(
                    enabled: true,
                    latitude: GoogleMapsCoordinateFixture.latitude,
                    longitude: GoogleMapsCoordinateFixture.longitude
                )
            ),
            supportsGoogleMaps: true
        ))

        XCTAssertTrue(systemInstruction.contains("Be concise."))
        XCTAssertTrue(systemInstruction.contains("Google Maps grounding is enabled"))
        XCTAssertTrue(systemInstruction.contains(GoogleMapsCoordinateFixture.instructionLatitudeFragment))
        XCTAssertTrue(systemInstruction.contains(GoogleMapsCoordinateFixture.instructionLongitudeFragment))
        XCTAssertTrue(systemInstruction.contains("do not ask the user for their location"))
    }

    func testSystemInstructionOmitsGoogleMapsLocationContextWhenUnsupported() throws {
        let systemInstruction = try XCTUnwrap(GeminiRequestSupport.systemInstructionText(
            from: [Message(role: .system, content: [.text("Be concise.")])],
            controls: GenerationControls(
                googleMaps: GoogleMapsControls(
                    enabled: true,
                    latitude: GoogleMapsCoordinateFixture.latitude,
                    longitude: GoogleMapsCoordinateFixture.longitude
                )
            ),
            supportsGoogleMaps: false
        ))

        XCTAssertEqual(systemInstruction, "Be concise.")
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
