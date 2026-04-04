import Foundation
import XCTest
@testable import Jin

final class GeminiAdapterTests: XCTestCase {
    func testGeminiAdapterBuildsGenerateContentRequestWithToolsThinkingAndNativePDF() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "g",
            name: "Gemini",
            type: .gemini,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        var uploadStartCount = 0
        var uploadFinalizeCount = 0

        protocolType.requestHandler = { request in
            if request.url?.absoluteString == "https://example.com/upload/files" {
                uploadStartCount += 1
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "test-key")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-Upload-Protocol"), "resumable")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-Upload-Command"), "start")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type"), "application/pdf")

                let body = try XCTUnwrap(requestBodyData(request))
                let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
                let file = try XCTUnwrap(root["file"] as? [String: Any])
                XCTAssertEqual(file["display_name"] as? String, "a.pdf")

                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["X-Goog-Upload-URL": "https://upload.example.com/gemini-session-1"]
                    )!,
                    Data()
                )
            }

            if request.url?.absoluteString == "https://upload.example.com/gemini-session-1" {
                uploadFinalizeCount += 1
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-Upload-Offset"), "0")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-Upload-Command"), "upload, finalize")

                let response: [String: Any] = [
                    "file": [
                        "name": "files/gemini-native-123",
                        "uri": "https://files.example.com/gemini-native-123",
                        "mime_type": "application/pdf"
                    ]
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data
                )
            }

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
            let fileData = try XCTUnwrap(parts.first?["fileData"] as? [String: Any])
            XCTAssertEqual(fileData["mimeType"] as? String, "application/pdf")
            XCTAssertEqual(fileData["fileUri"] as? String, "https://files.example.com/gemini-native-123")
            XCTAssertNil(parts.first?["inlineData"])

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
                ]
            ]
            let responseWithUsage: [String: Any] = [
                "candidates": response["candidates"]!,
                "usageMetadata": [
                    "promptTokenCount": 1,
                    "candidatesTokenCount": 2,
                    "totalTokenCount": 3
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: responseWithUsage)
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
        XCTAssertEqual(uploadStartCount, 1)
        XCTAssertEqual(uploadFinalizeCount, 1)
    }

    func testGeminiAdapterWaitsForHostedFileToBecomeActiveBeforeGenerateContent() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "g-processing",
            name: "Gemini",
            type: .gemini,
            apiKey: "ignored",
            baseURL: "https://processing.example.com"
        )

        var uploadStartCount = 0
        var uploadFinalizeCount = 0
        var fileStatusPollCount = 0

        protocolType.requestHandler = { request in
            if request.url?.absoluteString == "https://processing.example.com/upload/files" {
                uploadStartCount += 1
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["X-Goog-Upload-URL": "https://upload.example.com/gemini-processing-session-1"]
                    )!,
                    Data()
                )
            }

            if request.url?.absoluteString == "https://upload.example.com/gemini-processing-session-1" {
                uploadFinalizeCount += 1

                let response: [String: Any] = [
                    "file": [
                        "name": "files/gemini-processing-123",
                        "uri": "https://files.example.com/gemini-processing-123",
                        "mime_type": "application/pdf",
                        "state": "PROCESSING"
                    ]
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data
                )
            }

            if request.url?.absoluteString == "https://processing.example.com/files/gemini-processing-123" {
                fileStatusPollCount += 1
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "processing-key")

                let response: [String: Any] = [
                    "file": [
                        "name": "files/gemini-processing-123",
                        "uri": "https://files.example.com/gemini-processing-123",
                        "mime_type": "application/pdf",
                        "state": "ACTIVE"
                    ]
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data
                )
            }

            XCTAssertEqual(
                request.url?.absoluteString,
                "https://processing.example.com/models/gemini-3-flash-preview:generateContent"
            )

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let contents = try XCTUnwrap(json["contents"] as? [[String: Any]])
            let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
            let fileData = try XCTUnwrap(parts.first?["fileData"] as? [String: Any])
            XCTAssertEqual(fileData["fileUri"] as? String, "https://files.example.com/gemini-processing-123")

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
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        let adapter = GeminiAdapter(
            providerConfig: providerConfig,
            apiKey: "processing-key",
            networkManager: networkManager
        )

        let pdf = FileContent(
            mimeType: "application/pdf",
            filename: "processing.pdf",
            data: Data([0x25, 0x50, 0x44, 0x46, 0x2D, 0x50]),
            url: nil,
            extractedText: "HELLO"
        )

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [.file(pdf)])
            ],
            modelID: "gemini-3-flash-preview",
            controls: GenerationControls(pdfProcessingMode: .native),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}

        XCTAssertEqual(uploadStartCount, 1)
        XCTAssertEqual(uploadFinalizeCount, 1)
        XCTAssertEqual(fileStatusPollCount, 1)
    }

    func testGeminiAdapterBuildsGoogleMapsToolRequest() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "g-maps",
            name: "Gemini",
            type: .gemini,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/models/gemini-2.5-flash:generateContent")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let tools = try XCTUnwrap(json["tools"] as? [[String: Any]])
            XCTAssertEqual(tools.count, 1)

            let googleMaps = try XCTUnwrap(tools.first?["googleMaps"] as? [String: Any])
            XCTAssertEqual(googleMaps["enableWidget"] as? Bool, true)

            let toolConfig = try XCTUnwrap(json["toolConfig"] as? [String: Any])
            let retrievalConfig = try XCTUnwrap(toolConfig["retrievalConfig"] as? [String: Any])
            let latLng = try XCTUnwrap(retrievalConfig["latLng"] as? [String: Any])
            XCTAssertEqual(latLng["latitude"] as? Double, 34.050481)
            XCTAssertEqual(latLng["longitude"] as? Double, -118.248526)
            XCTAssertNil(retrievalConfig["languageCode"])

            let response: [String: Any] = [
                "candidates": [
                    [
                        "content": [
                            "parts": [
                                ["text": "Maps answer"]
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
            messages: [Message(role: .user, content: [.text("Find coffee near me")])],
            modelID: "gemini-2.5-flash",
            controls: GenerationControls(
                googleMaps: GoogleMapsControls(
                    enabled: true,
                    enableWidget: true,
                    latitude: 34.050481,
                    longitude: -118.248526,
                    languageCode: "en_US"
                )
            ),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testGeminiAdapterParsesThoughtAndFunctionCallAndUsage() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
                    "totalTokenCount": 7,
                    "cachedContentTokenCount": 2
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
        XCTAssertEqual(usage?.cachedTokens, 2)
    }

    func testGeminiAdapterUploadsPDFViaFilesAPIAndUsesFileDataURI() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "g",
            name: "Gemini",
            type: .gemini,
            apiKey: "ignored",
            baseURL: "https://example.com/v1beta"
        )

        var uploadStartCount = 0
        var uploadFinalizeCount = 0

        protocolType.requestHandler = { request in
            if request.url?.absoluteString == "https://example.com/upload/v1beta/files" {
                uploadStartCount += 1
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "test-key")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-Upload-Protocol"), "resumable")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-Upload-Command"), "start")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type"), "application/pdf")

                let body = try XCTUnwrap(requestBodyData(request))
                let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
                let file = try XCTUnwrap(root["file"] as? [String: Any])
                XCTAssertEqual(file["display_name"] as? String, "paper.pdf")

                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["X-Goog-Upload-URL": "https://upload.example.com/session-1"]
                    )!,
                    Data()
                )
            }

            if request.url?.absoluteString == "https://upload.example.com/session-1" {
                uploadFinalizeCount += 1
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-Upload-Offset"), "0")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-Upload-Command"), "upload, finalize")

                let response: [String: Any] = [
                    "file": [
                        "name": "files/gemini-123",
                        "uri": "https://files.example.com/gemini-123",
                        "mime_type": "application/pdf"
                    ]
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data
                )
            }

            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1beta/models/gemini-3-flash-preview:generateContent")

            let body = try XCTUnwrap(requestBodyData(request))
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let contents = try XCTUnwrap(root["contents"] as? [[String: Any]])
            let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
            let fileData = try XCTUnwrap(parts.first?["fileData"] as? [String: Any])
            XCTAssertEqual(fileData["mimeType"] as? String, "application/pdf")
            XCTAssertEqual(fileData["fileUri"] as? String, "https://files.example.com/gemini-123")
            XCTAssertNil(parts.first?["inlineData"])

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
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        let adapter = GeminiAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [
                Message(
                    role: .user,
                    content: [
                        .file(FileContent(
                            mimeType: "application/pdf",
                            filename: "paper.pdf",
                            data: Data([0x25, 0x50, 0x44, 0x46]),
                            url: nil,
                            extractedText: "PDF"
                        ))
                    ]
                )
            ],
            modelID: "gemini-3-flash-preview",
            controls: GenerationControls(pdfProcessingMode: .native),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
        XCTAssertEqual(uploadStartCount, 1)
        XCTAssertEqual(uploadFinalizeCount, 1)
    }

    func testGeminiAdapterBuildsCodeExecutionToolAndParsesExecutionParts() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "g",
            name: "Gemini",
            type: .gemini,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/models/gemini-3.1-pro-preview:generateContent")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            let tools = try XCTUnwrap(root["tools"] as? [[String: Any]])

            XCTAssertEqual(tools.count, 1)
            XCTAssertNotNil(tools.first?["code_execution"])

            let response: [String: Any] = [
                "candidates": [
                    [
                        "content": [
                            "parts": [
                                [
                                    "executableCode": [
                                        "language": "PYTHON",
                                        "code": "print(1)"
                                    ]
                                ],
                                [
                                    "codeExecutionResult": [
                                        "outcome": "OUTCOME_OK",
                                        "output": "1\n"
                                    ]
                                ],
                                [
                                    "text": "Done"
                                ]
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
                Message(role: .user, content: [.text("run python")])
            ],
            modelID: "gemini-3.1-pro-preview",
            controls: GenerationControls(codeExecution: CodeExecutionControls(enabled: true)),
            tools: [],
            streaming: false
        )

        var activities: [CodeExecutionActivity] = []
        var sawDoneText = false

        for try await event in stream {
            switch event {
            case .codeExecutionActivity(let activity):
                activities.append(activity)
            case .contentDelta(.text(let text)):
                sawDoneText = sawDoneText || text == "Done"
            default:
                break
            }
        }

        XCTAssertEqual(activities.count, 2)
        XCTAssertEqual(activities.first?.status, .writingCode)
        XCTAssertEqual(activities.first?.code, "print(1)")
        XCTAssertEqual(activities.last?.status, .completed)
        XCTAssertEqual(activities.last?.stdout, "1\n")
        XCTAssertEqual(activities.first?.id, activities.last?.id)
        XCTAssertTrue(sawDoneText)
    }

    func testGeminiAdapterEmitsSearchActivitiesFromGroundingMetadata() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
                                ["text": "Answer"]
                            ]
                        ],
                        "finishReason": "STOP",
                        "groundingMetadata": [
                            "webSearchQueries": [
                                "swift 6.2 release notes"
                            ],
                            "groundingChunks": [
                                [
                                    "web": [
                                        "uri": "https://example.com/swift-6-2",
                                        "title": "Swift 6.2"
                                    ]
                                ]
                            ],
                            "groundingSupports": [
                                [
                                    "segment": [
                                        "text": "Swift 6.2 includes stronger diagnostics for actor isolation and data-race safety."
                                    ],
                                    "groundingChunkIndices": [0]
                                ]
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
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gemini-3-flash-preview",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var searchEvents: [SearchActivity] = []
        for try await event in stream {
            if case .searchActivity(let activity) = event {
                searchEvents.append(activity)
            }
        }

        XCTAssertEqual(searchEvents.count, 2)
        XCTAssertEqual(searchEvents[0].type, "search")
        XCTAssertEqual(searchEvents[0].arguments["query"]?.value as? String, "swift 6.2 release notes")
        XCTAssertEqual(searchEvents[1].type, "open_page")
        XCTAssertEqual(searchEvents[1].arguments["url"]?.value as? String, "https://example.com/swift-6-2")
        XCTAssertEqual(searchEvents[1].arguments["title"]?.value as? String, "Swift 6.2")
        XCTAssertNil(searchEvents[1].arguments["snippet"]?.value)
    }

    func testGeminiAdapterSuppressesNativeGoogleSearchToolCallEvents() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "g-native-search",
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
                                    "functionCall": [
                                        "name": "google_search",
                                        "args": ["query": "how to swim across the sea"]
                                    ]
                                ],
                                ["text": "Answer"]
                            ]
                        ],
                        "groundingMetadata": [
                            "webSearchQueries": ["how to swim across the sea"]
                        ]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = GeminiAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gemini-3-flash-preview",
            controls: GenerationControls(webSearch: WebSearchControls(enabled: true)),
            tools: [],
            streaming: false
        )

        var toolCalls: [ToolCall] = []
        var searchEvents: [SearchActivity] = []

        for try await event in stream {
            switch event {
            case .toolCallStart(let call), .toolCallEnd(let call):
                toolCalls.append(call)
            case .searchActivity(let activity):
                searchEvents.append(activity)
            default:
                break
            }
        }

        XCTAssertTrue(toolCalls.isEmpty)
        XCTAssertEqual(searchEvents.first?.arguments["query"]?.value as? String, "how to swim across the sea")
    }

    func testGeminiAdapterEmitsSearchActivitiesFromTopLevelGroundingMetadataFallback() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
                                ["text": "Answer"]
                            ]
                        ],
                        "finishReason": "STOP"
                    ]
                ],
                "groundingMetadata": [
                    "webSearchQueries": [
                        "swift evolution"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = GeminiAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gemini-3-flash-preview",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var searchEvents: [SearchActivity] = []
        for try await event in stream {
            if case .searchActivity(let activity) = event {
                searchEvents.append(activity)
            }
        }

        XCTAssertEqual(searchEvents.count, 1)
        XCTAssertEqual(searchEvents[0].type, "search")
        XCTAssertEqual(searchEvents[0].arguments["query"]?.value as? String, "swift evolution")
    }

    func testGeminiAdapterEmitsSearchActivitiesFromRetrievalQueriesWithoutDuplicates() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
                                ["text": "Answer"]
                            ]
                        ],
                        "finishReason": "STOP",
                        "groundingMetadata": [
                            "webSearchQueries": ["Swift 6.2 release notes"],
                            "retrievalQueries": ["swift 6.2 release notes", "Swift actors"]
                        ]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = GeminiAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gemini-3-flash-preview",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var queries: [String] = []
        for try await event in stream {
            guard case .searchActivity(let activity) = event,
                  activity.type == "search",
                  let query = activity.arguments["query"]?.value as? String else { continue }
            queries.append(query)
        }

        XCTAssertEqual(queries, ["Swift 6.2 release notes", "Swift actors"])
    }

    func testGeminiAdapterFallsBackToSearchEntryPointSDKBlobWhenChunkURLsMissing() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "g",
            name: "Gemini",
            type: .gemini,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/models/gemini-3-flash-preview:generateContent")

            let sdkBlobPayload = [
                [
                    "query": "swift actor isolation",
                    "url": "https://www.google.com/search?q=swift+actor+isolation"
                ]
            ]
            let sdkBlobData = try JSONSerialization.data(withJSONObject: sdkBlobPayload)
            let sdkBlob = sdkBlobData.base64EncodedString()

            let response: [String: Any] = [
                "candidates": [
                    [
                        "content": [
                            "parts": [
                                ["text": "Answer"]
                            ]
                        ],
                        "finishReason": "STOP",
                        "groundingMetadata": [
                            "webSearchQueries": ["swift actor isolation"],
                            "searchEntryPoint": [
                                "sdkBlob": sdkBlob
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
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gemini-3-flash-preview",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var openPageEvents: [SearchActivity] = []
        for try await event in stream {
            guard case .searchActivity(let activity) = event, activity.type == "open_page" else { continue }
            openPageEvents.append(activity)
        }

        XCTAssertEqual(openPageEvents.count, 1)
        XCTAssertEqual(openPageEvents[0].arguments["url"]?.value as? String, "https://www.google.com/search?q=swift+actor+isolation")
        XCTAssertEqual(openPageEvents[0].arguments["title"]?.value as? String, "swift actor isolation")
    }

    func testGeminiAdapterFallsBackToTextWhenModeNotNative() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testGeminiAdapterUsesSpreadsheetFallbackPromptForXLSX() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "g-xlsx",
            name: "Gemini",
            type: .gemini,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/models/gemini-3-flash-preview:generateContent")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let contents = try XCTUnwrap(json["contents"] as? [[String: Any]])
            let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
            let text = try XCTUnwrap(parts.first?["text"] as? String)

            XCTAssertTrue(text.contains("does not provide .xlsx/.xls attachments as mounted local files"))
            XCTAssertTrue(text.contains("Sheet: Projects"))
            XCTAssertTrue(text.contains("Tokyo Exchange"))

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
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        let adapter = GeminiAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let xlsx = FileContent(
            mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            filename: "projects.xlsx",
            data: nil,
            url: nil,
            extractedText: "Sheet: Projects\n项目\t学校\nTokyo Exchange\t东京大学"
        )

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [.file(xlsx)])
            ],
            modelID: "gemini-3-flash-preview",
            controls: GenerationControls(codeExecution: CodeExecutionControls(enabled: true)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testGeminiAdapterClampsProMinimalThinkingLevelToLow() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "g",
            name: "Gemini",
            type: .gemini,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/models/gemini-3-pro-preview:generateContent")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let generationConfig = try XCTUnwrap(json["generationConfig"] as? [String: Any])
            let thinkingConfig = try XCTUnwrap(generationConfig["thinkingConfig"] as? [String: Any])
            XCTAssertEqual(thinkingConfig["thinkingLevel"] as? String, "LOW")

            let response: [String: Any] = [
                "candidates": [
                    [
                        "content": [
                            "parts": [
                                ["text": "ok"]
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
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gemini-3-pro-preview",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .minimal)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testGeminiAdapterKeeps31ProMediumThinkingLevel() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "g",
            name: "Gemini",
            type: .gemini,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/models/gemini-3.1-pro-preview:generateContent")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let generationConfig = try XCTUnwrap(json["generationConfig"] as? [String: Any])
            let thinkingConfig = try XCTUnwrap(generationConfig["thinkingConfig"] as? [String: Any])
            XCTAssertEqual(thinkingConfig["thinkingLevel"] as? String, "MEDIUM")

            let response: [String: Any] = [
                "candidates": [
                    [
                        "content": [
                            "parts": [
                                ["text": "ok"]
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
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gemini-3.1-pro-preview",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .medium)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testGeminiAdapterBuildsInlineDataForVideoInput() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            let contents = try XCTUnwrap(root["contents"] as? [[String: Any]])
            let first = try XCTUnwrap(contents.first)
            XCTAssertEqual(first["role"] as? String, "user")

            let parts = try XCTUnwrap(first["parts"] as? [[String: Any]])
            XCTAssertEqual(parts.count, 1)
            let inlineData = try XCTUnwrap(parts.first?["inlineData"] as? [String: Any])
            XCTAssertEqual(inlineData["mimeType"] as? String, "video/mp4")
            XCTAssertNotNil(inlineData["data"] as? String)

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
                    "candidatesTokenCount": 2
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = GeminiAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let video = VideoContent(mimeType: "video/mp4", data: Data([0x00, 0x01, 0x02]), url: nil)

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.video(video)])],
            modelID: "gemini-3-flash-preview",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testGeminiAdapterStreamingParsesSSEChunksAndEmitsUsage() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testGeminiAdapterSendsExplicitCachedContentWhenConfigured() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "g",
            name: "Gemini",
            type: .gemini,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/models/gemini-3-pro:generateContent")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["cachedContent"] as? String, "cachedContents/cache-123")

            let response: [String: Any] = [
                "candidates": [
                    [
                        "content": [
                            "parts": [
                                ["text": "ok"]
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
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gemini-3-pro",
            controls: GenerationControls(contextCache: ContextCacheControls(mode: .explicit, cachedContentName: "cachedContents/cache-123")),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testGeminiAdapterAddsResponseModalitiesForImageModels() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testGeminiProImageOmitsThinkingConfigWhenReasoningControlsArePresent() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let generationConfig = try XCTUnwrap(json["generationConfig"] as? [String: Any])
            XCTAssertNil(generationConfig["thinkingConfig"])

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
            messages: [Message(role: .user, content: [.text("draw")])],
            modelID: "gemini-3-pro-image-preview",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .high)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testGemini25FlashImageDoesNotSendToolsOrGoogleSearch() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testGeminiAdapterFetchModelsAppliesImageFallbackContextWindows() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "g",
            name: "Gemini",
            type: .gemini,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/models?pageSize=1000")

            // Simulate a response missing inputTokenLimit so fallback limits are exercised.
            let payload: [String: Any] = [
                "models": [
                    [
                        "name": "models/gemini-3-pro-image-preview",
                        "displayName": "Gemini 3 Pro Image Preview",
                        "supportedGenerationMethods": ["generateContent", "streamGenerateContent"]
                    ],
                    [
                        "name": "models/gemini-2.5-flash-image",
                        "displayName": "Gemini 2.5 Flash Image",
                        "supportedGenerationMethods": ["generateContent", "streamGenerateContent"]
                    ],
                    [
                        "name": "models/gemini-3.1-flash-image-preview",
                        "displayName": "Gemini 3.1 Flash Image Preview",
                        "supportedGenerationMethods": ["generateContent", "streamGenerateContent"]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = GeminiAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()
        let byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })

        let proImage = try XCTUnwrap(byID["gemini-3-pro-image-preview"])
        XCTAssertEqual(proImage.contextWindow, 65_536)
        XCTAssertTrue(proImage.capabilities.contains(.reasoning))
        XCTAssertNil(proImage.reasoningConfig)

        XCTAssertEqual(try XCTUnwrap(byID["gemini-2.5-flash-image"]).contextWindow, 65_536)
        let nanoBanana = try XCTUnwrap(byID["gemini-3.1-flash-image-preview"])
        XCTAssertEqual(nanoBanana.contextWindow, 131_072)
        XCTAssertTrue(nanoBanana.capabilities.contains(.nativePDF))
        XCTAssertTrue(nanoBanana.capabilities.contains(.reasoning))
        XCTAssertFalse(nanoBanana.capabilities.contains(.toolCalling))
        XCTAssertEqual(nanoBanana.reasoningConfig?.defaultEffort, .minimal)
    }

    func testGeminiAdapterFetchModelsUsesCatalogMetadataForGemma431() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "g",
            name: "Gemini",
            type: .gemini,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/models?pageSize=1000")

            let payload: [String: Any] = [
                "models": [
                    [
                        "name": "models/gemma-4-31b-it",
                        "displayName": "Gemma 4 31B",
                        "supportedGenerationMethods": ["generateContent", "streamGenerateContent"]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = GeminiAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()

        let model = try XCTUnwrap(models.first(where: { $0.id == "gemma-4-31b-it" }))
        XCTAssertEqual(model.contextWindow, 262_144)
        XCTAssertNil(model.maxOutputTokens)
        XCTAssertTrue(model.capabilities.contains(.streaming))
        XCTAssertTrue(model.capabilities.contains(.toolCalling))
        XCTAssertTrue(model.capabilities.contains(.vision))
        XCTAssertTrue(model.capabilities.contains(.reasoning))
        XCTAssertFalse(model.capabilities.contains(.audio))
        XCTAssertFalse(model.capabilities.contains(.nativePDF))
        XCTAssertFalse(model.capabilities.contains(.promptCaching))
        XCTAssertEqual(model.reasoningConfig?.defaultEffort, .medium)
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

private func makeMockedSessionConfiguration() -> (URLSessionConfiguration, MockURLProtocol.Type) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return (config, MockURLProtocol.self)
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
