import Foundation
import XCTest
@testable import Jin

final class PDFProcessingModeTests: XCTestCase {
    func testOpenAIAdapterSendsNativePDFWhenModeNative() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "o",
            name: "OpenAI",
            type: .openai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/responses")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            let input = try XCTUnwrap(root["input"] as? [[String: Any]])
            let first = try XCTUnwrap(input.first)
            let content = try XCTUnwrap(first["content"] as? [[String: Any]])

            XCTAssertTrue(content.contains { ($0["type"] as? String) == "input_file" })

            let response: [String: Any] = [
                "id": "resp_1",
                "output": [
                    [
                        "type": "message",
                        "content": [
                            ["type": "output_text", "text": "OK"]
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

        let adapter = OpenAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

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
            modelID: "gpt-5.2",
            controls: GenerationControls(pdfProcessingMode: .native),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testOpenAIAdapterDoesNotSendNativePDFForNonExactModelID() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "o",
            name: "OpenAI",
            type: .openai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/responses")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            let input = try XCTUnwrap(root["input"] as? [[String: Any]])
            let first = try XCTUnwrap(input.first)
            let content = try XCTUnwrap(first["content"] as? [[String: Any]])

            XCTAssertFalse(content.contains { ($0["type"] as? String) == "input_file" })

            let textParts = content.compactMap { item -> String? in
                guard (item["type"] as? String) == "input_text" else { return nil }
                return item["text"] as? String
            }
            XCTAssertEqual(textParts.count, 1)
            XCTAssertTrue(textParts[0].contains("PDF: a.pdf (application/pdf)"))

            let response: [String: Any] = [
                "id": "resp_1",
                "output": [
                    [
                        "type": "message",
                        "content": [
                            ["type": "output_text", "text": "OK"]
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

        let adapter = OpenAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

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
            modelID: "o4-mini",
            controls: GenerationControls(pdfProcessingMode: .native),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testOpenAIAdapterFallsBackToTextWhenModeNotNative() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "o",
            name: "OpenAI",
            type: .openai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/responses")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            let input = try XCTUnwrap(root["input"] as? [[String: Any]])
            let first = try XCTUnwrap(input.first)
            let content = try XCTUnwrap(first["content"] as? [[String: Any]])

            XCTAssertFalse(content.contains { ($0["type"] as? String) == "input_file" })

            let textParts = content.compactMap { item -> String? in
                guard (item["type"] as? String) == "input_text" else { return nil }
                return item["text"] as? String
            }
            XCTAssertEqual(textParts.count, 1)
            XCTAssertTrue(textParts[0].contains("PDF: a.pdf (application/pdf)"))
            XCTAssertTrue(textParts[0].contains("HELLO"))

            let response: [String: Any] = [
                "id": "resp_1",
                "output": [
                    [
                        "type": "message",
                        "content": [
                            ["type": "output_text", "text": "OK"]
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

        let adapter = OpenAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

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
            modelID: "gpt-5.2",
            controls: GenerationControls(pdfProcessingMode: .macOSExtract),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testOpenAIAdapterStillSendsNativeNonPDFWhenModeNotNative() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "o",
            name: "OpenAI",
            type: .openai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/responses")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            let input = try XCTUnwrap(root["input"] as? [[String: Any]])
            let first = try XCTUnwrap(input.first)
            let content = try XCTUnwrap(first["content"] as? [[String: Any]])

            let inputFile = try XCTUnwrap(content.first { ($0["type"] as? String) == "input_file" })
            XCTAssertEqual(inputFile["filename"] as? String, "a.docx")
            let fileData = try XCTUnwrap(inputFile["file_data"] as? String)
            XCTAssertTrue(fileData.hasPrefix("data:application/vnd.openxmlformats-officedocument.wordprocessingml.document;base64,"))
            XCTAssertFalse(content.contains { ($0["type"] as? String) == "input_text" })

            let response: [String: Any] = [
                "id": "resp_1",
                "output": [
                    [
                        "type": "message",
                        "content": [
                            ["type": "output_text", "text": "OK"]
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

        let adapter = OpenAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let docx = FileContent(
            mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            filename: "a.docx",
            data: Data([0x50, 0x4B, 0x03, 0x04]),
            url: nil,
            extractedText: "HELLO"
        )

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [.file(docx)])
            ],
            modelID: "gpt-5.2",
            controls: GenerationControls(pdfProcessingMode: .macOSExtract),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testOpenAIAdapterFallsBackToTextForVideoInput() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "o",
            name: "OpenAI",
            type: .openai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/responses")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            let input = try XCTUnwrap(root["input"] as? [[String: Any]])
            let first = try XCTUnwrap(input.first)
            let content = try XCTUnwrap(first["content"] as? [[String: Any]])

            let textParts = content.compactMap { item -> String? in
                guard (item["type"] as? String) == "input_text" else { return nil }
                return item["text"] as? String
            }
            XCTAssertEqual(textParts.count, 1)
            XCTAssertTrue(textParts[0].contains("Video attachment omitted"))
            XCTAssertTrue(textParts[0].contains("video/mp4"))

            let response: [String: Any] = [
                "id": "resp_1",
                "output": [
                    [
                        "type": "message",
                        "content": [
                            ["type": "output_text", "text": "OK"]
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

        let adapter = OpenAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let video = VideoContent(mimeType: "video/mp4", data: Data([0x00, 0x01, 0x02]), url: nil)

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [.video(video)])
            ],
            modelID: "gpt-5.2",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testXAIAdapterDoesNotSendNativePDFForNonExactModelID() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/responses")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            let input = try XCTUnwrap(root["input"] as? [[String: Any]])
            let first = try XCTUnwrap(input.first)
            let content = try XCTUnwrap(first["content"] as? [[String: Any]])

            XCTAssertFalse(content.contains { ($0["type"] as? String) == "input_file" })
            let textParts = content.compactMap { item -> String? in
                guard (item["type"] as? String) == "input_text" else { return nil }
                return item["text"] as? String
            }
            XCTAssertEqual(textParts.count, 1)
            XCTAssertTrue(textParts[0].contains("PDF: a.pdf (application/pdf)"))

            let response: [String: Any] = [
                "id": "resp_1",
                "output": [
                    [
                        "type": "message",
                        "content": [
                            ["type": "output_text", "text": "OK"]
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

        let adapter = XAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
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
            modelID: "grok-5",
            controls: GenerationControls(pdfProcessingMode: .native),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testAnthropicAdapterDisablesNativePDFWhenModeNotNative() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "a",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/messages")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 1)

            let first = try XCTUnwrap(messages.first)
            let content = try XCTUnwrap(first["content"] as? [[String: Any]])

            XCTAssertFalse(content.contains { ($0["type"] as? String) == "document" })

            let textBlocks = content.compactMap { item -> String? in
                guard (item["type"] as? String) == "text" else { return nil }
                return item["text"] as? String
            }
            XCTAssertEqual(textBlocks.count, 1)
            XCTAssertTrue(textBlocks[0].contains("PDF: a.pdf (application/pdf)"))
            XCTAssertTrue(textBlocks[0].contains("HELLO"))

            // Minimal SSE body; stop after [DONE].
            let data = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

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
            modelID: "claude-sonnet-4-5-20250929",
            controls: GenerationControls(pdfProcessingMode: .macOSExtract),
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testAnthropicAdapterFallsBackToTextForVideoInput() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "a",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/messages")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
            let first = try XCTUnwrap(messages.first)
            let content = try XCTUnwrap(first["content"] as? [[String: Any]])

            let textBlocks = content.compactMap { item -> String? in
                guard (item["type"] as? String) == "text" else { return nil }
                return item["text"] as? String
            }
            XCTAssertEqual(textBlocks.count, 1)
            XCTAssertTrue(textBlocks[0].contains("Video attachment omitted"))
            XCTAssertTrue(textBlocks[0].contains("video/mp4"))

            let data = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let video = VideoContent(mimeType: "video/mp4", data: Data([0x00, 0x01, 0x02]), url: nil)

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [.video(video)])
            ],
            modelID: "claude-sonnet-4-5-20250929",
            controls: GenerationControls(),
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testMistralOCRClientBuildsDocumentUrlRequest() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/ocr")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "mistral-ocr-latest")
            XCTAssertEqual(root["include_image_base64"] as? Bool, false)

            let document = try XCTUnwrap(root["document"] as? [String: Any])
            XCTAssertEqual(document["type"] as? String, "document_url")
            let url = try XCTUnwrap(document["document_url"] as? String)
            XCTAssertTrue(url.hasPrefix("data:application/pdf;base64,"))

            let response: [String: Any] = [
                "pages": [
                    ["index": 0, "markdown": "Hello"]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        let client = MistralOCRClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://example.com/v1")!,
            networkManager: networkManager
        )

        let response = try await client.ocrPDF(Data("PDF".utf8))
        XCTAssertEqual(response.pages.count, 1)
        XCTAssertEqual(response.pages[0].markdown, "Hello")
    }

    func testDeepInfraDeepSeekOCRClientBuildsChatCompletionsRequest() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/openai/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "deepseek-ai/DeepSeek-OCR")
            XCTAssertEqual((root["max_tokens"] as? NSNumber)?.intValue, 64)
            XCTAssertEqual((root["temperature"] as? NSNumber)?.doubleValue, 0)

            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 1)
            let message = try XCTUnwrap(messages.first)
            XCTAssertEqual(message["role"] as? String, "user")

            let content = try XCTUnwrap(message["content"] as? [[String: Any]])
            XCTAssertEqual(content.count, 2)
            XCTAssertEqual(content[0]["type"] as? String, "image_url")
            let imageURL = try XCTUnwrap(content[0]["image_url"] as? [String: Any])
            let url = try XCTUnwrap(imageURL["url"] as? String)
            XCTAssertTrue(url.hasPrefix("data:image/jpeg;base64,"))
            XCTAssertTrue(url.contains("SU1H")) // "IMG" base64

            XCTAssertEqual(content[1]["type"] as? String, "text")
            XCTAssertEqual(content[1]["text"] as? String, "Hello OCR")

            let response: [String: Any] = [
                "choices": [
                    [
                        "message": [
                            "content": "OK"
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

        let client = DeepInfraDeepSeekOCRClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://example.com/v1/openai")!,
            networkManager: networkManager
        )

        let text = try await client.ocrImage(
            Data("IMG".utf8),
            mimeType: "image/jpeg",
            prompt: "Hello OCR",
            maxTokens: 64
        )
        XCTAssertEqual(text, "OK")
    }

    func testDeepInfraDeepSeekOCRClientValidateAPIKeyUsesJPEGImage() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/openai/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
            let message = try XCTUnwrap(messages.first)
            let content = try XCTUnwrap(message["content"] as? [[String: Any]])
            XCTAssertEqual(content.count, 2)

            let imageURL = try XCTUnwrap(content[0]["image_url"] as? [String: Any])
            let url = try XCTUnwrap(imageURL["url"] as? String)
            XCTAssertTrue(url.hasPrefix("data:image/jpeg;base64,"))
            XCTAssertTrue(url.contains("/9j/"))

            XCTAssertEqual(content[1]["type"] as? String, "text")

            let response: [String: Any] = [
                "choices": [
                    [
                        "message": [
                            "content": "OK"
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

        let client = DeepInfraDeepSeekOCRClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://example.com/v1/openai")!,
            networkManager: networkManager
        )

        try await client.validateAPIKey(timeoutSeconds: 5)
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
