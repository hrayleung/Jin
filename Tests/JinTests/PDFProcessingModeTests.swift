import AppKit
import Foundation
import PDFKit
import XCTest
@testable import Jin

final class PDFProcessingModeTests: XCTestCase {
    func testDefaultPDFProcessingFallbackModePrefersExistingConfiguredOCRBeforeMinerU() {
        XCTAssertEqual(
            ChatModelCapabilitySupport.defaultPDFProcessingFallbackMode(
                mistralOCRPluginEnabled: true,
                mistralOCRConfigured: true,
                mineruOCRPluginEnabled: true,
                mineruOCRConfigured: true,
                deepSeekOCRPluginEnabled: true,
                deepSeekOCRConfigured: true,
                openRouterOCRPluginEnabled: true,
                openRouterOCRConfigured: true,
                firecrawlOCRPluginEnabled: true,
                firecrawlOCRConfigured: true
            ),
            .mistralOCR
        )
    }

    func testDefaultPDFProcessingFallbackModeUsesMinerUWhenItIsFirstConfiguredFallback() {
        XCTAssertEqual(
            ChatModelCapabilitySupport.defaultPDFProcessingFallbackMode(
                mistralOCRPluginEnabled: false,
                mistralOCRConfigured: false,
                mineruOCRPluginEnabled: true,
                mineruOCRConfigured: true,
                deepSeekOCRPluginEnabled: true,
                deepSeekOCRConfigured: true,
                openRouterOCRPluginEnabled: true,
                openRouterOCRConfigured: true,
                firecrawlOCRPluginEnabled: true,
                firecrawlOCRConfigured: true
            ),
            .mineruOCR
        )
    }

    func testDefaultPDFProcessingFallbackModeUsesOpenRouterBeforeFirecrawl() {
        XCTAssertEqual(
            ChatModelCapabilitySupport.defaultPDFProcessingFallbackMode(
                mistralOCRPluginEnabled: false,
                mistralOCRConfigured: false,
                mineruOCRPluginEnabled: false,
                mineruOCRConfigured: false,
                deepSeekOCRPluginEnabled: false,
                deepSeekOCRConfigured: false,
                openRouterOCRPluginEnabled: true,
                openRouterOCRConfigured: true,
                firecrawlOCRPluginEnabled: true,
                firecrawlOCRConfigured: true
            ),
            .openRouterOCR
        )
    }

    func testDefaultPDFProcessingFallbackModeUsesFirecrawlBeforeMacOSExtract() {
        XCTAssertEqual(
            ChatModelCapabilitySupport.defaultPDFProcessingFallbackMode(
                mistralOCRPluginEnabled: false,
                mistralOCRConfigured: false,
                mineruOCRPluginEnabled: false,
                mineruOCRConfigured: false,
                deepSeekOCRPluginEnabled: false,
                deepSeekOCRConfigured: false,
                openRouterOCRPluginEnabled: false,
                openRouterOCRConfigured: false,
                firecrawlOCRPluginEnabled: true,
                firecrawlOCRConfigured: true
            ),
            .firecrawlOCR
        )
    }

    func testResolvedPDFProcessingModeAcceptsMinerUWhenEnabled() {
        XCTAssertEqual(
            ChatModelCapabilitySupport.resolvedPDFProcessingMode(
                controls: GenerationControls(pdfProcessingMode: .mineruOCR),
                supportsNativePDF: false,
                defaultPDFProcessingFallbackMode: .macOSExtract,
                mistralOCRPluginEnabled: false,
                mineruOCRPluginEnabled: true,
                deepSeekOCRPluginEnabled: false,
                openRouterOCRPluginEnabled: false,
                firecrawlOCRPluginEnabled: false
            ),
            .mineruOCR
        )
    }

    func testResolvedPDFProcessingModeAcceptsOpenRouterWhenEnabled() {
        XCTAssertEqual(
            ChatModelCapabilitySupport.resolvedPDFProcessingMode(
                controls: GenerationControls(pdfProcessingMode: .openRouterOCR),
                supportsNativePDF: false,
                defaultPDFProcessingFallbackMode: .macOSExtract,
                mistralOCRPluginEnabled: false,
                mineruOCRPluginEnabled: false,
                deepSeekOCRPluginEnabled: false,
                openRouterOCRPluginEnabled: true,
                firecrawlOCRPluginEnabled: false
            ),
            .openRouterOCR
        )
    }

    func testResolvedPDFProcessingModeAcceptsFirecrawlWhenEnabled() {
        XCTAssertEqual(
            ChatModelCapabilitySupport.resolvedPDFProcessingMode(
                controls: GenerationControls(pdfProcessingMode: .firecrawlOCR),
                supportsNativePDF: false,
                defaultPDFProcessingFallbackMode: .macOSExtract,
                mistralOCRPluginEnabled: false,
                mineruOCRPluginEnabled: false,
                deepSeekOCRPluginEnabled: false,
                openRouterOCRPluginEnabled: false,
                firecrawlOCRPluginEnabled: true
            ),
            .firecrawlOCR
        )
    }

    func testGenerationControlsRoundTripPreservesFirecrawlParserMode() throws {
        let controls = GenerationControls(
            pdfProcessingMode: .firecrawlOCR,
            firecrawlPDFParserMode: .fast
        )

        let data = try JSONEncoder().encode(controls)
        let decoded = try JSONDecoder().decode(GenerationControls.self, from: data)

        XCTAssertEqual(decoded.pdfProcessingMode, .firecrawlOCR)
        XCTAssertEqual(decoded.firecrawlPDFParserMode, .fast)
    }

    func testResolveExtensionCredentialStatusIncludesOpenRouterOCRKey() {
        let suiteName = "PDFProcessingModeTests.openrouter.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AppPreferences.setPluginEnabled(true, for: "openrouter_ocr", defaults: defaults)
        var status = ChatConversationStateSupport.resolveExtensionCredentialStatus(defaults: defaults)
        XCTAssertFalse(status.openRouterOCRConfigured)
        XCTAssertTrue(status.openRouterOCRPluginEnabled)

        defaults.set("test-key", forKey: AppPreferenceKeys.pluginOpenRouterOCRAPIKey)
        status = ChatConversationStateSupport.resolveExtensionCredentialStatus(defaults: defaults)
        XCTAssertTrue(status.openRouterOCRConfigured)
    }

    func testOpenAIAdapterSendsNativePDFWhenModeNative() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "o",
            name: "OpenAI",
            type: .openai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        var uploadCount = 0

        protocolType.requestHandler = { request in
            switch request.url?.path {
            case "/files":
                uploadCount += 1
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

                let body = try XCTUnwrap(requestBodyData(request))
                let bodyString = try XCTUnwrap(String(bytes: body, encoding: .utf8))
                XCTAssertTrue(bodyString.contains("name=\"purpose\""))
                XCTAssertTrue(bodyString.contains("user_data"))
                XCTAssertTrue(bodyString.contains("name=\"file\""))
                XCTAssertTrue(bodyString.contains("filename=\"a.pdf\""))

                let response: [String: Any] = [
                    "id": "file_pdf_123",
                    "filename": "a.pdf"
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data
                )

            case "/responses":
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

                let body = try XCTUnwrap(requestBodyData(request))
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                let root = try XCTUnwrap(json)

                let input = try XCTUnwrap(root["input"] as? [[String: Any]])
                let first = try XCTUnwrap(input.first)
                let content = try XCTUnwrap(first["content"] as? [[String: Any]])
                let inputFile = try XCTUnwrap(content.first { ($0["type"] as? String) == "input_file" })
                XCTAssertEqual(inputFile["file_id"] as? String, "file_pdf_123")
                XCTAssertNil(inputFile["file_data"])
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

            default:
                XCTFail("Unexpected request: \(request.url?.absoluteString ?? "<nil>")")
                let data = try JSONSerialization.data(withJSONObject: [:])
                return (
                    HTTPURLResponse(url: request.url ?? URL(string: "https://example.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                    data
                )
            }
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
        XCTAssertEqual(uploadCount, 1)
    }

    func testOpenAIAdapterDoesNotSendNativePDFForNonExactModelID() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "o",
            name: "OpenAI",
            type: .openai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        var uploadCount = 0

        protocolType.requestHandler = { request in
            switch request.url?.path {
            case "/files":
                uploadCount += 1
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

                let body = try XCTUnwrap(requestBodyData(request))
                let bodyString = try XCTUnwrap(String(bytes: body, encoding: .utf8))
                XCTAssertTrue(bodyString.contains("name=\"purpose\""))
                XCTAssertTrue(bodyString.contains("user_data"))
                XCTAssertTrue(bodyString.contains("name=\"file\""))
                XCTAssertTrue(bodyString.contains("filename=\"a.docx\""))

                let response: [String: Any] = [
                    "id": "file_docx_123",
                    "filename": "a.docx"
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data
                )

            case "/responses":
                let body = try XCTUnwrap(requestBodyData(request))
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                let root = try XCTUnwrap(json)

                let input = try XCTUnwrap(root["input"] as? [[String: Any]])
                let first = try XCTUnwrap(input.first)
                let content = try XCTUnwrap(first["content"] as? [[String: Any]])

                let inputFile = try XCTUnwrap(content.first { ($0["type"] as? String) == "input_file" })
                XCTAssertEqual(inputFile["file_id"] as? String, "file_docx_123")
                XCTAssertNil(inputFile["file_data"])
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

            default:
                XCTFail("Unexpected request: \(request.url?.absoluteString ?? "<nil>")")
                let data = try JSONSerialization.data(withJSONObject: [:])
                return (
                    HTTPURLResponse(url: request.url ?? URL(string: "https://example.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                    data
                )
            }
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
        XCTAssertEqual(uploadCount, 1)
    }

    func testOpenAIAdapterFallsBackToTextForVideoInput() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testMinerUOCRClientBootstrapsUploadAndExtractsFullMarkdown() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)
        let archiveData = try makeZipArchive(entries: ["full.md": "# Hello MinerU"])

        protocolType.requestHandler = { request in
            switch (request.url?.host, request.url?.path) {
            case ("example.com", "/api/v4/file-urls/batch"):
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
                XCTAssertEqual(request.value(forHTTPHeaderField: "token"), "user-123")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

                let body = try XCTUnwrap(requestBodyData(request))
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(json["enable_formula"] as? Bool, true)
                XCTAssertEqual(json["enable_table"] as? Bool, true)
                XCTAssertEqual(json["language"] as? String, "en")
                XCTAssertEqual(json["model_version"] as? String, "vlm")

                let files = try XCTUnwrap(json["files"] as? [[String: Any]])
                XCTAssertEqual(files.count, 1)
                XCTAssertEqual(files[0]["name"] as? String, "scan.pdf")
                XCTAssertEqual(files[0]["is_ocr"] as? Bool, true)
                XCTAssertNotNil(files[0]["data_id"] as? String)

                let response: [String: Any] = [
                    "code": 0,
                    "msg": "ok",
                    "data": [
                        "batch_id": "batch_123",
                        "file_urls": ["https://upload.example.com/upload.pdf"]
                    ]
                ]
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    try JSONSerialization.data(withJSONObject: response)
                )

            case ("upload.example.com", "/upload.pdf"):
                XCTAssertEqual(request.httpMethod, "PUT")
                XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
                XCTAssertEqual(requestBodyData(request), Data("PDF".utf8))
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data()
                )

            case ("example.com", "/api/v4/extract-results/batch/batch_123"):
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
                let response: [String: Any] = [
                    "code": 0,
                    "msg": "ok",
                    "data": [
                        "extract_result": [
                            [
                                "state": "done",
                                "full_zip_url": "https://cdn.example.com/result.zip"
                            ]
                        ]
                    ]
                ]
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    try JSONSerialization.data(withJSONObject: response)
                )

            case ("cdn.example.com", "/result.zip"):
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    archiveData
                )

            default:
                XCTFail("Unexpected request: \(request.url?.absoluteString ?? "<nil>")")
                return (
                    HTTPURLResponse(url: request.url ?? URL(string: "https://example.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            }
        }

        let client = MinerUOCRClient(
            apiToken: "test-token",
            userToken: "user-123",
            baseURL: URL(string: "https://example.com")!,
            networkManager: networkManager
        )

        let markdown = try await client.ocrPDF(
            Data("PDF".utf8),
            filename: "scan.pdf",
            language: "en",
            timeoutSeconds: 5,
            pollIntervalNanoseconds: 1_000_000
        )
        XCTAssertEqual(markdown, "# Hello MinerU")
    }

    func testMinerUOCRClientExtractsNestedFullMarkdownFromArchive() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)
        let archiveData = try makeZipArchive(entries: ["results/full.md": "# Nested MinerU"])

        protocolType.requestHandler = { request in
            switch (request.url?.host, request.url?.path) {
            case ("example.com", "/api/v4/file-urls/batch"):
                let response: [String: Any] = [
                    "code": 0,
                    "msg": "ok",
                    "data": [
                        "batch_id": "batch_nested",
                        "file_urls": ["https://upload.example.com/upload-nested.pdf"]
                    ]
                ]
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    try JSONSerialization.data(withJSONObject: response)
                )

            case ("upload.example.com", "/upload-nested.pdf"):
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data()
                )

            case ("example.com", "/api/v4/extract-results/batch/batch_nested"):
                let response: [String: Any] = [
                    "code": 0,
                    "msg": "ok",
                    "data": [
                        "extract_result": [
                            [
                                "state": "done",
                                "full_zip_url": "https://cdn.example.com/nested.zip"
                            ]
                        ]
                    ]
                ]
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    try JSONSerialization.data(withJSONObject: response)
                )

            case ("cdn.example.com", "/nested.zip"):
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    archiveData
                )

            default:
                XCTFail("Unexpected request: \(request.url?.absoluteString ?? "<nil>")")
                return (
                    HTTPURLResponse(url: request.url ?? URL(string: "https://example.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            }
        }

        let client = MinerUOCRClient(
            apiToken: "test-token",
            baseURL: URL(string: "https://example.com")!,
            networkManager: networkManager
        )

        let markdown = try await client.ocrPDF(
            Data("PDF".utf8),
            filename: "nested.pdf",
            timeoutSeconds: 5,
            pollIntervalNanoseconds: 1_000_000
        )
        XCTAssertEqual(markdown, "# Nested MinerU")
    }

    func testDeepInfraDeepSeekOCRClientBuildsChatCompletionsRequest() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testOpenRouterOCRClientBuildsChatCompletionsRequest() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "HTTP-Referer"), "https://jin.app")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Title"), "Jin")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

            XCTAssertEqual(json["model"] as? String, "baidu/qianfan-ocr-fast:free")
            XCTAssertEqual((json["max_tokens"] as? NSNumber)?.intValue, 64)
            XCTAssertEqual((json["temperature"] as? NSNumber)?.doubleValue, 0)

            let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 1)
            let message = try XCTUnwrap(messages.first)
            XCTAssertEqual(message["role"] as? String, "user")

            let content = try XCTUnwrap(message["content"] as? [[String: Any]])
            XCTAssertEqual(content.count, 2)

            XCTAssertEqual(content[0]["type"] as? String, "text")
            XCTAssertEqual(content[0]["text"] as? String, "Hello OCR")

            XCTAssertEqual(content[1]["type"] as? String, "image_url")
            let imageURL = try XCTUnwrap(content[1]["image_url"] as? [String: Any])
            let url = try XCTUnwrap(imageURL["url"] as? String)
            XCTAssertTrue(url.hasPrefix("data:image/jpeg;base64,"))
            XCTAssertTrue(url.contains("SU1H"))

            let response: [String: Any] = [
                "choices": [
                    [
                        "message": [
                            "content": "OK"
                        ]
                    ]
                ]
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: response)
            )
        }

        let client = OpenRouterOCRClient(
            apiKey: "test-key",
            modelID: "baidu/qianfan-ocr-fast:free",
            baseURL: URL(string: "https://example.com/v1")!,
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

    func testOpenRouterOCRClientValidateAPIKeyUsesJPEGImage() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual((json["max_tokens"] as? NSNumber)?.intValue, 16)
            let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
            let message = try XCTUnwrap(messages.first)
            let content = try XCTUnwrap(message["content"] as? [[String: Any]])
            XCTAssertEqual(content.count, 2)

            XCTAssertEqual(content[0]["type"] as? String, "text")
            XCTAssertEqual(content[0]["text"] as? String, "Reply with exactly: OK")

            let imageURL = try XCTUnwrap(content[1]["image_url"] as? [String: Any])
            let url = try XCTUnwrap(imageURL["url"] as? String)
            XCTAssertTrue(url.hasPrefix("data:image/jpeg;base64,"))
            XCTAssertTrue(url.contains("/9j/"))

            let response: [String: Any] = [
                "choices": [
                    [
                        "message": [
                            "content": "OK"
                        ]
                    ]
                ]
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: response)
            )
        }

        let client = OpenRouterOCRClient(
            apiKey: "test-key",
            modelID: "baidu/qianfan-ocr-fast:free",
            baseURL: URL(string: "https://example.com/v1")!,
            networkManager: networkManager
        )

        try await client.validateAPIKey(timeoutSeconds: 5)
    }

    func testOpenRouterOCRClientSurfacesChoiceLevelErrors() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            let response: [String: Any] = [
                "choices": [
                    [
                        "finish_reason": "error",
                        "error": [
                            "code": 429,
                            "message": "Provider quota exceeded"
                        ]
                    ]
                ]
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: response)
            )
        }

        let client = OpenRouterOCRClient(
            apiKey: "test-key",
            modelID: "baidu/qianfan-ocr-fast:free",
            baseURL: URL(string: "https://example.com/v1")!,
            networkManager: networkManager
        )

        do {
            _ = try await client.ocrImage(
                Data("IMG".utf8),
                mimeType: "image/jpeg",
                prompt: "Hello OCR",
                maxTokens: 64
            )
            XCTFail("Expected OpenRouter OCR choice-level error to be surfaced")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Provider quota exceeded"))
            XCTAssertTrue(error.localizedDescription.contains("429"))
        }
    }

    func testPreparedContentForPDFOpenRouterRequiresAPIKey() async throws {
        let attachment = try makeValidPDFDraftAttachment(pageCount: 1)
        defer { try? FileManager.default.removeItem(at: attachment.fileURL) }

        do {
            _ = try await ChatMessagePreparationSupport.preparedContentForPDF(
                attachment,
                profile: makeOpenRouterProfile(supportsVision: false),
                requestedMode: .openRouterOCR,
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
            XCTFail("Expected OpenRouter OCR to require an API key")
        } catch let error as PDFProcessingError {
            XCTAssertEqual(error.localizedDescription, PDFProcessingError.openRouterOCRAPIKeyMissing.localizedDescription)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPreparedContentForPDFOpenRouterBuildsMarkdownOutputAndAttachesPageImagesForVision() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)
        let attachment = try makeValidPDFDraftAttachment(pageCount: 2)
        defer { try? FileManager.default.removeItem(at: attachment.fileURL) }

        var requestCount = 0
        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "HTTP-Referer"), "https://jin.app")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Title"), "Jin")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "baidu/qianfan-ocr-fast:free")

            requestCount += 1
            let content: String
            switch requestCount {
            case 1:
                content = "```markdown\n# Page One\n```"
            case 2:
                content = "## Page Two"
            default:
                XCTFail("Unexpected extra OCR request")
                content = ""
            }

            let response: [String: Any] = [
                "choices": [
                    [
                        "message": [
                            "content": content
                        ]
                    ]
                ]
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: response)
            )
        }

        let client = OpenRouterOCRClient(
            apiKey: "test-key",
            modelID: "baidu/qianfan-ocr-fast:free",
            baseURL: URL(string: "https://example.com/v1")!,
            networkManager: networkManager
        )

        let prepared = try await ChatMessagePreparationSupport.preparedContentForPDF(
            attachment,
            profile: makeOpenRouterProfile(supportsVision: true),
            requestedMode: .openRouterOCR,
            totalPDFCount: 1,
            pdfOrdinal: 1,
            mistralClient: nil,
            mineruClient: nil,
            deepSeekClient: nil,
            openRouterClient: client,
            firecrawlClient: nil,
            r2Uploader: nil,
            onStatusUpdate: { _ in }
        )

        XCTAssertEqual(requestCount, 2)
        XCTAssertTrue(prepared.extractedText?.hasPrefix("OpenRouter OCR (Qianfan OCR Fast (free) Markdown): scan.pdf") == true)
        XCTAssertTrue(prepared.extractedText?.contains("# Page One\n\n## Page Two") == true)
        XCTAssertEqual(prepared.additionalParts.count, 2)
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

private func makeOpenRouterProfile(supportsVision: Bool) -> ChatMessagePreparationSupport.MessagePreparationProfile {
    ChatMessagePreparationSupport.MessagePreparationProfile(
        threadID: UUID(),
        modelName: "Test Model",
        supportsVideoGenerationControl: false,
        supportsMediaGenerationControl: false,
        supportsNativePDF: false,
        supportsVision: supportsVision,
        pdfProcessingMode: .openRouterOCR,
        firecrawlPDFParserMode: .ocr
    )
}

private func makeValidPDFDraftAttachment(pageCount: Int) throws -> DraftAttachment {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("jin-openrouter-ocr-\(UUID().uuidString).pdf")
    let document = PDFDocument()

    for index in 0..<pageCount {
        let image = NSImage(size: NSSize(width: 360, height: 240))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 360, height: 240)).fill()
        let text = "Page \(index + 1)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 28, weight: .medium),
            .foregroundColor: NSColor.black
        ]
        text.draw(at: NSPoint(x: 24, y: 96), withAttributes: attributes)
        image.unlockFocus()

        let page = try XCTUnwrap(PDFPage(image: image))
        document.insert(page, at: index)
    }

    let data = try XCTUnwrap(document.dataRepresentation())
    try data.write(to: url, options: .atomic)

    return DraftAttachment(
        id: UUID(),
        filename: "scan.pdf",
        mimeType: "application/pdf",
        fileURL: url,
        extractedText: nil
    )
}

private func makeZipArchive(entries: [String: String]) throws -> Data {
    let fileManager = FileManager.default
    let zipPath = "/usr/bin/zip"
    guard fileManager.isExecutableFile(atPath: zipPath) else {
        throw XCTSkip("zip binary not available at \(zipPath)")
    }

    let rootURL = fileManager.temporaryDirectory
        .appendingPathComponent("JinZipArchive-\(UUID().uuidString)", isDirectory: true)
    let contentURL = rootURL.appendingPathComponent("content", isDirectory: true)
    let archiveURL = rootURL.appendingPathComponent("archive.zip", isDirectory: false)

    try fileManager.createDirectory(at: contentURL, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: rootURL) }

    for (path, content) in entries {
        let fileURL = contentURL.appendingPathComponent(path, isDirectory: false)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: fileURL, options: .atomic)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: zipPath)
    process.currentDirectoryURL = contentURL
    process.arguments = ["-q", "-r", archiveURL.path, "."]

    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)

    return try Data(contentsOf: archiveURL)
}
