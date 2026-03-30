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
                    latitude: 34.050481,
                    longitude: -118.248526,
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
        XCTAssertEqual(latLng["latitude"] as? Double, 34.050481)
        XCTAssertEqual(latLng["longitude"] as? Double, -118.248526)
        XCTAssertEqual(retrievalConfig["languageCode"] as? String, "en_US")
        XCTAssertNotNil(json["safetySettings"])
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
}
