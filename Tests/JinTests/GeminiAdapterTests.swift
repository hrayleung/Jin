import Foundation
import XCTest
@testable import Jin

final class GeminiAdapterTests: XCTestCase {
    func testGeminiAdapterBuildsGenerateContentRequestWithToolsThinkingAndNativePDF() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "g",
            name: "Gemini",
            type: .gemini,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/models/gemini-3-flash-preview:generateContent")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "test-key")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            let systemInstruction = try XCTUnwrap(root["systemInstruction"] as? [String: Any])
            let systemParts = try XCTUnwrap(systemInstruction["parts"] as? [[String: Any]])
            XCTAssertEqual(systemParts.first?["text"] as? String, "sys")

            let contents = try XCTUnwrap(root["contents"] as? [[String: Any]])
            XCTAssertEqual(contents.count, 1)

            let first = try XCTUnwrap(contents.first)
            XCTAssertEqual(first["role"] as? String, "user")

            let parts = try XCTUnwrap(first["parts"] as? [[String: Any]])
            XCTAssertEqual(parts.count, 1)
            let inlineData = try XCTUnwrap(parts.first?["inlineData"] as? [String: Any])
            XCTAssertEqual(inlineData["mimeType"] as? String, "application/pdf")
            XCTAssertNotNil(inlineData["data"] as? String)

            let generationConfig = try XCTUnwrap(root["generationConfig"] as? [String: Any])
            let thinkingConfig = try XCTUnwrap(generationConfig["thinkingConfig"] as? [String: Any])
            XCTAssertEqual(thinkingConfig["includeThoughts"] as? Bool, true)
            XCTAssertEqual(thinkingConfig["thinkingLevel"] as? String, "MEDIUM")

            let tools = try XCTUnwrap(root["tools"] as? [[String: Any]])
            XCTAssertEqual(tools.count, 2)
            XCTAssertNotNil(tools.first?["google_search"])
            let functionContainer = try XCTUnwrap(tools.last?["functionDeclarations"] as? [[String: Any]])
            XCTAssertEqual(functionContainer.count, 1)
            XCTAssertEqual(functionContainer.first?["name"] as? String, "tool_name")

            let response: [String: Any] = [
                "candidates": [
                    [
                        "content": [
                            "parts": [
                                ["text": "OK"]
                            ]
                        ]
                    ]
                ],
                "usageMetadata": [
                    "promptTokenCount": 1,
                    "candidatesTokenCount": 2,
                    "totalTokenCount": 3
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = GeminiAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let tool = ToolDefinition(
            id: "t",
            name: "tool_name",
            description: "desc",
            parameters: ParameterSchema(
                properties: [
                    "q": PropertySchema(type: "string", description: "query")
                ],
                required: ["q"]
            ),
            source: .builtin
        )

        let pdf = FileContent(
            mimeType: "application/pdf",
            filename: "a.pdf",
            data: Data([0x25, 0x50, 0x44, 0x46]),
            url: nil,
            extractedText: "HELLO"
        )

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .system, content: [.text("sys")]),
                Message(role: .user, content: [.file(pdf)])
            ],
            modelID: "gemini-3-flash-preview",
            controls: GenerationControls(
                reasoning: ReasoningControls(enabled: true, effort: .medium),
                webSearch: WebSearchControls(enabled: true),
                pdfProcessingMode: .native
            ),
            tools: [tool],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testGeminiAdapterParsesThoughtAndFunctionCallAndUsage() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "g",
            name: "Gemini",
            type: .gemini,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/models/gemini-3-flash-preview:generateContent")

            let response: [String: Any] = [
                "candidates": [
                    [
                        "content": [
                            "parts": [
                                [
                                    "text": "T",
                                    "thought": true,
                                    "thoughtSignature": "sig"
                                ],
                                [
                                    "functionCall": [
                                        "name": "tool_name",
                                        "args": ["q": "x"]
                                    ],
                                    "thoughtSignature": "sig2"
                                ],
                                [
                                    "text": "A"
                                ]
                            ]
                        ],
                        "finishReason": "STOP"
                    ]
                ],
                "usageMetadata": [
                    "promptTokenCount": 3,
                    "candidatesTokenCount": 4,
                    "totalTokenCount": 7
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = GeminiAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [.text("hi")])
            ],
            modelID: "gemini-3-flash-preview",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 6)

        guard case .messageStart = events[0] else { return XCTFail("Expected messageStart") }

        guard case .thinkingDelta(.thinking(let thoughtText, let sig)) = events[1] else { return XCTFail("Expected thinkingDelta") }
        XCTAssertEqual(thoughtText, "T")
        XCTAssertEqual(sig, "sig")

        guard case .toolCallStart(let call) = events[2] else { return XCTFail("Expected toolCallStart") }
        XCTAssertEqual(call.name, "tool_name")
        XCTAssertEqual(call.arguments["q"]?.value as? String, "x")
        XCTAssertEqual(call.signature, "sig2")

        guard case .toolCallEnd(let endCall) = events[3] else { return XCTFail("Expected toolCallEnd") }
        XCTAssertEqual(endCall.name, "tool_name")
        XCTAssertEqual(endCall.arguments["q"]?.value as? String, "x")
        XCTAssertEqual(endCall.signature, "sig2")

        guard case .contentDelta(.text(let content)) = events[4] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(content, "A")

        guard case .messageEnd(let usage) = events[5] else { return XCTFail("Expected messageEnd") }
        XCTAssertEqual(usage?.inputTokens, 3)
        XCTAssertEqual(usage?.outputTokens, 4)
    }

    func testGeminiAdapterFallsBackToTextWhenModeNotNative() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "g",
            name: "Gemini",
            type: .gemini,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/models/gemini-3-flash-preview:generateContent")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            let contents = try XCTUnwrap(root["contents"] as? [[String: Any]])
            let first = try XCTUnwrap(contents.first)
            let parts = try XCTUnwrap(first["parts"] as? [[String: Any]])

            XCTAssertFalse(parts.contains { $0["inlineData"] != nil })
            let textParts = parts.compactMap { $0["text"] as? String }
            XCTAssertEqual(textParts.count, 1)
            XCTAssertTrue(textParts[0].contains("PDF: a.pdf (application/pdf)"))
            XCTAssertTrue(textParts[0].contains("HELLO"))

            let response: [String: Any] = [
                "candidates": [
                    [
                        "content": [
                            "parts": [
                                ["text": "OK"]
                            ]
                        ]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = GeminiAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let pdf = FileContent(
            mimeType: "application/pdf",
            filename: "a.pdf",
            data: Data([0x25, 0x50, 0x44, 0x46]),
            url: nil,
            extractedText: "HELLO"
        )

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [.file(pdf)])
            ],
            modelID: "gemini-3-flash-preview",
            controls: GenerationControls(pdfProcessingMode: .macOSExtract),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testGeminiAdapterStreamingParsesSSEChunksAndEmitsUsage() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "g",
            name: "Gemini",
            type: .gemini,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/models/gemini-3-flash-preview:streamGenerateContent?alt=sse")

            let sse = [
                "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hi\"}]}}]}\n\n",
                "data: {\"usageMetadata\":{\"promptTokenCount\":1,\"candidatesTokenCount\":2,\"totalTokenCount\":3}}\n\n"
            ].joined()
            let data = Data(sse.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = GeminiAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [.text("hi")])
            ],
            modelID: "gemini-3-flash-preview",
            controls: GenerationControls(),
            tools: [],
            streaming: true
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 3)

        guard case .messageStart = events[0] else { return XCTFail("Expected messageStart") }
        guard case .contentDelta(.text(let delta)) = events[1] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(delta, "Hi")

        guard case .messageEnd(let usage) = events[2] else { return XCTFail("Expected messageEnd") }
        XCTAssertEqual(usage?.inputTokens, 1)
        XCTAssertEqual(usage?.outputTokens, 2)
    }

    func testGeminiAdapterAddsResponseModalitiesForImageModels() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "g",
            name: "Gemini",
            type: .gemini,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/models/gemini-3-pro-image-preview:generateContent")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            let generationConfig = try XCTUnwrap(root["generationConfig"] as? [String: Any])
            let responseModalities = try XCTUnwrap(generationConfig["responseModalities"] as? [String])
            XCTAssertEqual(responseModalities, ["TEXT", "IMAGE"])

            let response: [String: Any] = [
                "candidates": [
                    [
                        "content": [
                            "parts": [
                                ["text": "OK"]
                            ]
                        ]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = GeminiAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [.text("draw")])
            ],
            modelID: "gemini-3-pro-image-preview",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testGemini25FlashImageDoesNotSendToolsOrGoogleSearch() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "g",
            name: "Gemini",
            type: .gemini,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/models/gemini-2.5-flash-image:generateContent")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertNil(root["tools"])

            let response: [String: Any] = [
                "candidates": [
                    [
                        "content": [
                            "parts": [
                                ["text": "Done"]
                            ]
                        ]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = GeminiAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let tool = ToolDefinition(
            id: "t",
            name: "tool_name",
            description: "desc",
            parameters: ParameterSchema(
                properties: [
                    "q": PropertySchema(type: "string", description: "query")
                ],
                required: ["q"]
            ),
            source: .builtin
        )

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [.text("draw a lake")])
            ],
            modelID: "gemini-2.5-flash-image",
            controls: GenerationControls(webSearch: WebSearchControls(enabled: true)),
            tools: [tool],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testGeminiAdapterUsesImageGenerationControlsForImageModels() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "g",
            name: "Gemini",
            type: .gemini,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/models/gemini-3-pro-image-preview:generateContent")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            let generationConfig = try XCTUnwrap(root["generationConfig"] as? [String: Any])
            let responseModalities = try XCTUnwrap(generationConfig["responseModalities"] as? [String])
            XCTAssertEqual(responseModalities, ["IMAGE"])
            XCTAssertEqual(generationConfig["seed"] as? Int, 1234)

            let imageConfig = try XCTUnwrap(generationConfig["imageConfig"] as? [String: Any])
            XCTAssertEqual(imageConfig["aspectRatio"] as? String, "16:9")
            XCTAssertEqual(imageConfig["imageSize"] as? String, "2K")

            let tools = try XCTUnwrap(root["tools"] as? [[String: Any]])
            XCTAssertEqual(tools.count, 1)
            XCTAssertNotNil(tools.first?["google_search"])
            XCTAssertNil(tools.first?["functionDeclarations"])

            let response: [String: Any] = [
                "candidates": [
                    [
                        "content": [
                            "parts": [
                                ["text": "Done"]
                            ]
                        ]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = GeminiAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let tool = ToolDefinition(
            id: "t",
            name: "tool_name",
            description: "desc",
            parameters: ParameterSchema(
                properties: [
                    "q": PropertySchema(type: "string", description: "query")
                ],
                required: ["q"]
            ),
            source: .builtin
        )

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [.text("draw a lake")])
            ],
            modelID: "gemini-3-pro-image-preview",
            controls: GenerationControls(
                webSearch: WebSearchControls(enabled: true),
                imageGeneration: ImageGenerationControls(
                    responseMode: .imageOnly,
                    aspectRatio: .ratio16x9,
                    imageSize: .size2K,
                    seed: 1234
                )
            ),
            tools: [tool],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testGeminiAdapterParsesInlineDataImageAsContentDeltaImage() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "g",
            name: "Gemini",
            type: .gemini,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        let expectedData = Data([0x01, 0x02, 0x03])
        let expectedBase64 = expectedData.base64EncodedString()

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/models/gemini-3-pro-image-preview:generateContent")

            let response: [String: Any] = [
                "candidates": [
                    [
                        "content": [
                            "parts": [
                                [
                                    "inlineData": [
                                        "mimeType": "image/png",
                                        "data": expectedBase64
                                    ]
                                ],
                                ["text": "Done"]
                            ]
                        ]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = GeminiAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [.text("draw")])
            ],
            modelID: "gemini-3-pro-image-preview",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var images: [ImageContent] = []
        for try await event in stream {
            if case .contentDelta(.image(let image)) = event {
                images.append(image)
            }
        }

        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0].mimeType, "image/png")
        XCTAssertEqual(images[0].data, expectedData)
    }
}

// MARK: - URLProtocol stubbing

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeMockedURLSession() -> (URLSession, MockURLProtocol.Type) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return (URLSession(configuration: config), MockURLProtocol.self)
}

private func requestBodyData(_ request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else { return nil }

    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 16 * 1024
    var buffer = [UInt8](repeating: 0, count: bufferSize)

    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: bufferSize)
        if read < 0 {
            return nil
        }
        if read == 0 {
            break
        }
        data.append(buffer, count: read)
    }

    return data
}
