import Foundation
import XCTest
@testable import Jin

final class VertexAIRequestBuilderTests: XCTestCase {
    func testBuildRequestUsesCachedContentAndOmitsSystemInstructionForExplicitCache() throws {
        let builder = VertexAIRequestBuilder(
            providerConfig: makeVertexProviderConfig(),
            serviceAccountJSON: makeVertexCredentials(),
            modelSupport: VertexAIModelSupport()
        )

        let request = try builder.buildRequest(
            messages: [
                Message(role: .system, content: [.text("system instruction")]),
                Message(role: .user, content: [.text("hello")])
            ],
            modelID: "gemini-2.5-flash",
            controls: GenerationControls(
                contextCache: ContextCacheControls(
                    mode: .explicit,
                    cachedContentName: "cachedContents/abc123"
                )
            ),
            tools: [],
            streaming: true,
            accessToken: "vertex-token"
        )

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://aiplatform.googleapis.com/v1/projects/project/locations/global/publishers/google/models/gemini-2.5-flash:streamGenerateContent"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer vertex-token")

        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(vertexAIRequestBodyData(request))) as? [String: Any])
        XCTAssertEqual(json["cachedContent"] as? String, "cachedContents/abc123")
        XCTAssertNil(json["systemInstruction"])
    }

    func testBuildRequestCombinesAllSystemMessageTextPartsIntoSystemInstruction() throws {
        let builder = VertexAIRequestBuilder(
            providerConfig: makeVertexProviderConfig(),
            serviceAccountJSON: makeVertexCredentials(),
            modelSupport: VertexAIModelSupport()
        )

        let request = try builder.buildRequest(
            messages: [
                Message(role: .system, content: [.text("First"), .image(ImageContent(mimeType: "image/png", data: Data())), .text("Second")]),
                Message(role: .user, content: [.text("hello")]),
                Message(role: .system, content: [.text("Third"), .text("Fourth")])
            ],
            modelID: "gemini-2.5-flash",
            controls: GenerationControls(),
            tools: [],
            streaming: false,
            accessToken: "vertex-token"
        )

        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(vertexAIRequestBodyData(request))) as? [String: Any])
        let systemInstruction = try XCTUnwrap(json["systemInstruction"] as? [String: Any])
        let parts = try XCTUnwrap(systemInstruction["parts"] as? [[String: Any]])

        XCTAssertEqual(parts.map { $0["text"] as? String }, ["First", "Second", "Third", "Fourth"])
    }

    func testBuildRequestIncludesGoogleMapsToolConfigAndProviderSpecificOverrides() throws {
        let builder = VertexAIRequestBuilder(
            providerConfig: makeVertexProviderConfig(),
            serviceAccountJSON: makeVertexCredentials(),
            modelSupport: VertexAIModelSupport()
        )

        let request = try builder.buildRequest(
            messages: [Message(role: .user, content: [.text("Find coffee near me")])],
            modelID: "gemini-2.5-flash",
            controls: GenerationControls(
                googleMaps: GoogleMapsControls(
                    enabled: true,
                    enableWidget: true,
                    latitude: GoogleMapsCoordinateFixture.latitude,
                    longitude: GoogleMapsCoordinateFixture.longitude,
                    languageCode: "en_US"
                ),
                providerSpecific: [
                    "safetySettings": AnyCodable([["category": "HARM_CATEGORY_HATE_SPEECH"]])
                ]
            ),
            tools: [],
            streaming: false,
            accessToken: "vertex-token"
        )

        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(vertexAIRequestBodyData(request))) as? [String: Any])
        let tools = try XCTUnwrap(json["tools"] as? [[String: Any]])
        let googleMaps = try XCTUnwrap(tools.first?["googleMaps"] as? [String: Any], "Expected googleMaps tool")
        XCTAssertEqual(googleMaps["enableWidget"] as? Bool, true)

        let toolConfig = try XCTUnwrap(json["toolConfig"] as? [String: Any])
        let retrievalConfig = try XCTUnwrap(toolConfig["retrievalConfig"] as? [String: Any])
        let latLng = try XCTUnwrap(retrievalConfig["latLng"] as? [String: Any])
        XCTAssertEqual(latLng["latitude"] as? Double, GoogleMapsCoordinateFixture.latitude)
        XCTAssertEqual(latLng["longitude"] as? Double, GoogleMapsCoordinateFixture.longitude)
        XCTAssertEqual(retrievalConfig["languageCode"] as? String, "en_US")
        let systemInstruction = try XCTUnwrap(json["systemInstruction"] as? [String: Any])
        let systemParts = try XCTUnwrap(systemInstruction["parts"] as? [[String: Any]])
        let systemText = try XCTUnwrap(systemParts.first?["text"] as? String)
        XCTAssertTrue(systemText.contains("Google Maps grounding is enabled"))
        XCTAssertTrue(systemText.contains(GoogleMapsCoordinateFixture.instructionLatitudeFragment))
        XCTAssertTrue(systemText.contains(GoogleMapsCoordinateFixture.instructionLongitudeFragment))
        XCTAssertNotNil(json["safetySettings"])
    }

    func testBuildRequestIncludesGoogleMapsForVertexGemini3FlashPreview() throws {
        let builder = VertexAIRequestBuilder(
            providerConfig: makeVertexProviderConfig(),
            serviceAccountJSON: makeVertexCredentials(),
            modelSupport: VertexAIModelSupport()
        )

        let request = try builder.buildRequest(
            messages: [Message(role: .user, content: [.text("Find food nearby")])],
            modelID: "gemini-3-flash-preview",
            controls: GenerationControls(
                webSearch: WebSearchControls(enabled: true),
                googleMaps: GoogleMapsControls(
                    enabled: true,
                    enableWidget: true,
                    latitude: GoogleMapsCoordinateFixture.latitude,
                    longitude: GoogleMapsCoordinateFixture.longitude,
                    languageCode: "en_US"
                )
            ),
            tools: [],
            streaming: false,
            accessToken: "vertex-token"
        )

        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(vertexAIRequestBodyData(request))) as? [String: Any]
        )
        let tools = try XCTUnwrap(json["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 2)
        XCTAssertTrue(tools.contains { $0["googleSearch"] != nil })
        XCTAssertTrue(tools.contains { $0["googleMaps"] != nil })
        XCTAssertNotNil(json["toolConfig"])
    }

    func testGenerationConfigOmitsCustomSamplingForGemini36Flash() {
        let builder = VertexAIRequestBuilder(
            providerConfig: makeVertexProviderConfig(),
            serviceAccountJSON: makeVertexCredentials(),
            modelSupport: VertexAIModelSupport()
        )

        let config = builder.makeGenerationConfig(
            GenerationControls(temperature: 0.1, maxTokens: 512, topP: 0.2),
            modelID: "gemini-3.6-flash"
        )

        XCTAssertNil(config["temperature"])
        XCTAssertNil(config["topP"])
        XCTAssertEqual(config["maxOutputTokens"] as? Int, 512)
    }

    func testBuildRequestUsesStandardParametersKeyForFunctionDeclarations() throws {
        let builder = VertexAIRequestBuilder(
            providerConfig: makeVertexProviderConfig(),
            serviceAccountJSON: makeVertexCredentials(),
            modelSupport: VertexAIModelSupport()
        )

        let request = try builder.buildRequest(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "gemini-2.5-flash",
            controls: GenerationControls(),
            tools: [ToolDefinition(
                id: "weather",
                name: "weather",
                description: "Fetches the weather",
                parameters: ParameterSchema(
                    properties: [
                        "city": PropertySchema(type: "string", description: "City name")
                    ],
                    required: ["city"]
                ),
                source: .builtin
            )],
            streaming: false,
            accessToken: "vertex-token"
        )

        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(vertexAIRequestBodyData(request))) as? [String: Any])
        let tools = try XCTUnwrap(json["tools"] as? [[String: Any]])
        let declarations = try XCTUnwrap(tools.first?["functionDeclarations"] as? [[String: Any]])
        let declaration = try XCTUnwrap(declarations.first)

        XCTAssertNotNil(declaration["parameters"])
        XCTAssertNil(declaration["parametersJsonSchema"])
    }

    func testBuildRequestPreservesAssistantThinkingPartOrder() throws {
        let builder = VertexAIRequestBuilder(
            providerConfig: makeVertexProviderConfig(),
            serviceAccountJSON: makeVertexCredentials(),
            modelSupport: VertexAIModelSupport()
        )

        let request = try builder.buildRequest(
            messages: [
                Message(
                    role: .assistant,
                    content: [
                        .text("preface"),
                        .thinking(ThinkingBlock(text: "analysis", signature: "sig")),
                        .text("suffix")
                    ]
                )
            ],
            modelID: "gemini-2.5-flash",
            controls: GenerationControls(),
            tools: [],
            streaming: false,
            accessToken: "vertex-token"
        )

        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(vertexAIRequestBodyData(request))) as? [String: Any])
        let contents = try XCTUnwrap(json["contents"] as? [[String: Any]])
        let first = try XCTUnwrap(contents.first)
        let parts = try XCTUnwrap(first["parts"] as? [[String: Any]])

        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts[0]["text"] as? String, "preface")
        XCTAssertEqual(parts[1]["text"] as? String, "analysis")
        XCTAssertEqual(parts[1]["thought"] as? Bool, true)
        XCTAssertEqual(parts[2]["text"] as? String, "suffix")
    }

    func testBuildRequestIncludesImageGenerationConfigForKnownImagenModel() throws {
        let builder = VertexAIRequestBuilder(
            providerConfig: makeVertexProviderConfig(),
            serviceAccountJSON: makeVertexCredentials(),
            modelSupport: VertexAIModelSupport()
        )

        let request = try builder.buildRequest(
            messages: [Message(role: .user, content: [.text("Draw a lantern floating over the sea")])],
            modelID: "imagen-4.0-generate-preview-06-06",
            controls: GenerationControls(
                imageGeneration: ImageGenerationControls(
                    responseMode: .imageOnly,
                    aspectRatio: .ratio16x9,
                    seed: 42,
                    vertexPersonGeneration: .allowAdult,
                    vertexOutputMIMEType: .png
                )
            ),
            tools: [],
            streaming: false,
            accessToken: "vertex-token"
        )

        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(vertexAIRequestBodyData(request))) as? [String: Any])
        let generationConfig = try XCTUnwrap(json["generationConfig"] as? [String: Any])
        XCTAssertEqual(generationConfig["responseModalities"] as? [String], ["IMAGE"])
        XCTAssertEqual(generationConfig["seed"] as? Int, 42)

        let imageConfig = try XCTUnwrap(generationConfig["imageConfig"] as? [String: Any])
        XCTAssertEqual(imageConfig["aspectRatio"] as? String, ImageAspectRatio.ratio16x9.rawValue)
        XCTAssertEqual(imageConfig["personGeneration"] as? String, VertexImagePersonGeneration.allowAdult.rawValue)

        let outputOptions = try XCTUnwrap(imageConfig["imageOutputOptions"] as? [String: Any])
        XCTAssertEqual(outputOptions["mimeType"] as? String, VertexImageOutputMIMEType.png.rawValue)
    }

    func testBuildRequestKeepsUnknownImagenModelsConservative() throws {
        let builder = VertexAIRequestBuilder(
            providerConfig: makeVertexProviderConfig(),
            serviceAccountJSON: makeVertexCredentials(),
            modelSupport: VertexAIModelSupport()
        )

        let request = try builder.buildRequest(
            messages: [Message(role: .user, content: [.text("Draw a lantern floating over the sea")])],
            modelID: "imagen-custom-experiment",
            controls: GenerationControls(
                reasoning: ReasoningControls(enabled: true, effort: .high),
                imageGeneration: ImageGenerationControls(
                    responseMode: .imageOnly,
                    aspectRatio: .ratio16x9,
                    seed: 42,
                    vertexPersonGeneration: .allowAdult,
                    vertexOutputMIMEType: .png
                )
            ),
            tools: [ToolDefinition(
                id: "weather",
                name: "weather",
                description: "Fetches the weather",
                parameters: ParameterSchema(
                    properties: [
                        "city": PropertySchema(type: "string", description: "City name")
                    ],
                    required: ["city"]
                ),
                source: .builtin
            )],
            streaming: false,
            accessToken: "vertex-token"
        )

        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(vertexAIRequestBodyData(request))) as? [String: Any])
        let generationConfig = try XCTUnwrap(json["generationConfig"] as? [String: Any])

        XCTAssertNil(generationConfig["thinkingConfig"])
        XCTAssertNil(generationConfig["responseModalities"])
        XCTAssertNil(generationConfig["seed"])
        XCTAssertNil(generationConfig["imageConfig"])
        XCTAssertNil(json["tools"])
    }

    func testBuildRequestNormalizesModelPathsToTerminalModelID() throws {
        let builder = VertexAIRequestBuilder(
            providerConfig: makeVertexProviderConfig(),
            serviceAccountJSON: makeVertexCredentials(),
            modelSupport: VertexAIModelSupport()
        )

        let request = try builder.buildRequest(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "publishers/google/models/gemini-2.5-flash",
            controls: GenerationControls(),
            tools: [],
            streaming: false,
            accessToken: "vertex-token"
        )

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://aiplatform.googleapis.com/v1/projects/project/locations/global/publishers/google/models/gemini-2.5-flash:generateContent"
        )
    }

    func testBuildRequestNormalizesModelsPrefixToTerminalModelID() throws {
        let builder = VertexAIRequestBuilder(
            providerConfig: makeVertexProviderConfig(),
            serviceAccountJSON: makeVertexCredentials(),
            modelSupport: VertexAIModelSupport()
        )

        let request = try builder.buildRequest(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "models/gemini-2.5-flash",
            controls: GenerationControls(),
            tools: [],
            streaming: true,
            accessToken: "vertex-token"
        )

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://aiplatform.googleapis.com/v1/projects/project/locations/global/publishers/google/models/gemini-2.5-flash:streamGenerateContent"
        )
    }

    func testModelEndpointNormalizesPathPrefixedModelID() {
        let builder = VertexAIRequestBuilder(
            providerConfig: makeVertexProviderConfig(),
            serviceAccountJSON: makeVertexCredentials(),
            modelSupport: VertexAIModelSupport()
        )

        // modelEndpoint normalizes, so video-generation callers (predictLongRunning /
        // fetchPredictOperation) get the same canonical path the chat path uses.
        XCTAssertEqual(
            builder.modelEndpoint(modelID: "publishers/google/models/veo-3.0-generate-001", verb: "predictLongRunning"),
            "https://aiplatform.googleapis.com/v1/projects/project/locations/global/publishers/google/models/veo-3.0-generate-001:predictLongRunning"
        )
        // Already-terminal ids are unchanged (normalization is idempotent).
        XCTAssertEqual(
            builder.modelEndpoint(modelID: "veo-3.0-generate-001", verb: "fetchPredictOperation"),
            "https://aiplatform.googleapis.com/v1/projects/project/locations/global/publishers/google/models/veo-3.0-generate-001:fetchPredictOperation"
        )
    }

    func testResolvedLocationFallsBackToGlobalForBlankLocation() {
        XCTAssertEqual(makeVertexCredentials(location: "").resolvedLocation, "global")
        XCTAssertEqual(makeVertexCredentials(location: "   ").resolvedLocation, "global")
        XCTAssertEqual(makeVertexCredentials(location: "us-central1").resolvedLocation, "us-central1")
        // A blank location must not produce an invalid "https://-aiplatform..." host.
        XCTAssertEqual(makeVertexCredentials(location: "").vertexBaseURL, "https://aiplatform.googleapis.com/v1")
    }
}
