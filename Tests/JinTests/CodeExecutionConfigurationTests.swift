import Foundation
import XCTest
@testable import Jin

final class CodeExecutionConfigurationTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testOpenAIAdapterBuildsAutoContainerCodeInterpreterConfiguration() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "openai",
            name: "OpenAI",
            type: .openai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/responses")

            let body = try XCTUnwrap(requestBodyData(request))
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let tools = try XCTUnwrap(root["tools"] as? [[String: Any]])
            let codeInterpreter = try XCTUnwrap(
                tools.first { ($0["type"] as? String) == "code_interpreter" }
            )
            let container = try XCTUnwrap(codeInterpreter["container"] as? [String: Any])

            XCTAssertEqual(container["type"] as? String, "auto")
            XCTAssertEqual(container["memory_limit"] as? String, "4g")
            XCTAssertEqual(container["file_ids"] as? [String], ["file_alpha", "file_beta"])

            let include = try XCTUnwrap(root["include"] as? [String])
            XCTAssertTrue(include.contains("code_interpreter_call.outputs"))

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

        let adapter = OpenAIAdapter(
            providerConfig: providerConfig,
            apiKey: "test-key",
            networkManager: networkManager
        )

        let controls = GenerationControls(
            codeExecution: CodeExecutionControls(
                enabled: true,
                openAI: OpenAICodeExecutionOptions(
                    container: CodeExecutionContainer(
                        type: "auto",
                        memoryLimit: "4g",
                        fileIDs: [" file_alpha ", "file_beta", "file_alpha"]
                    )
                )
            )
        )

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("run code")])],
            modelID: "gpt-5.2",
            controls: controls,
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testOpenAIAdapterUsesExistingContainerIDWhenConfigured() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "openai",
            name: "OpenAI",
            type: .openai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let tools = try XCTUnwrap(root["tools"] as? [[String: Any]])
            let codeInterpreter = try XCTUnwrap(
                tools.first { ($0["type"] as? String) == "code_interpreter" }
            )

            XCTAssertEqual(codeInterpreter["container"] as? String, "cntr_existing_123")

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

        let adapter = OpenAIAdapter(
            providerConfig: providerConfig,
            apiKey: "test-key",
            networkManager: networkManager
        )

        let controls = GenerationControls(
            codeExecution: CodeExecutionControls(
                enabled: true,
                openAI: OpenAICodeExecutionOptions(existingContainerID: " cntr_existing_123 ")
            )
        )

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("reuse container")])],
            modelID: "gpt-5.2",
            controls: controls,
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testOpenAIAdapterSkipsCodeExecutionForUnsupportedModel() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "openai",
            name: "OpenAI",
            type: .openai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let tools = (root["tools"] as? [[String: Any]]) ?? []
            XCTAssertFalse(tools.contains { ($0["type"] as? String) == "code_interpreter" })

            let include = (root["include"] as? [String]) ?? []
            XCTAssertFalse(include.contains("code_interpreter_call.outputs"))

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

        let adapter = OpenAIAdapter(
            providerConfig: providerConfig,
            apiKey: "test-key",
            networkManager: networkManager
        )

        let controls = GenerationControls(
            codeExecution: CodeExecutionControls(enabled: true)
        )

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("run code")])],
            modelID: "gpt-4o",
            controls: controls,
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testAnthropicAdapterUsesContainerUploadAndFilesAPIBetaWhenCodeExecutionEnabled() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "anthropic",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        var uploadCount = 0

        protocolType.requestHandler = { request in
            switch request.url?.path {
            case "/files":
                uploadCount += 1
                XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), anthropicFilesAPIBetaHeader)

                let response: [String: Any] = [
                    "id": "file_ant_123",
                    "filename": "dataset.csv",
                    "mime_type": "text/csv"
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data
                )

            case "/messages":
                XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), anthropicFilesAPIBetaHeader)

                let body = try XCTUnwrap(requestBodyData(request))
                let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(root["container"] as? String, "container_abc123")

                let tools = try XCTUnwrap(root["tools"] as? [[String: Any]])
                let codeExecutionTool = try XCTUnwrap(
                    tools.first { ($0["type"] as? String) == "code_execution_20250825" }
                )
                XCTAssertEqual(codeExecutionTool["name"] as? String, "code_execution")

                let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
                let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
                let uploadBlock = try XCTUnwrap(content.first)
                XCTAssertEqual(uploadBlock["type"] as? String, "container_upload")
                XCTAssertEqual(uploadBlock["file_id"] as? String, "file_ant_123")

                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("data: [DONE]\n\n".utf8)
                )

            default:
                XCTFail("Unexpected request: \(request.url?.absoluteString ?? "<nil>")")
                return (
                    HTTPURLResponse(url: request.url ?? URL(string: "https://example.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            }
        }

        let adapter = AnthropicAdapter(
            providerConfig: providerConfig,
            apiKey: "test-key",
            networkManager: networkManager
        )

        let csv = FileContent(
            mimeType: "text/csv",
            filename: "dataset.csv",
            data: Data("a,b\n1,2\n".utf8),
            url: nil,
            extractedText: "a,b\n1,2"
        )

        let controls = GenerationControls(
            codeExecution: CodeExecutionControls(
                enabled: true,
                anthropic: AnthropicCodeExecutionOptions(containerID: " container_abc123 ")
            )
        )

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.file(csv)])],
            modelID: "claude-opus-4-6",
            controls: controls,
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
        XCTAssertEqual(uploadCount, 1)
    }

    func testAnthropicAdapterUploadsXLSXAsContainerUploadWhenCodeExecutionEnabled() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "anthropic",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        var uploadCount = 0

        protocolType.requestHandler = { request in
            switch request.url?.path {
            case "/files":
                uploadCount += 1
                let body = try XCTUnwrap(requestBodyData(request))
                let bodyString = try XCTUnwrap(String(data: body, encoding: .utf8))
                XCTAssertTrue(bodyString.contains("filename=\"projects.xlsx\""))

                let response: [String: Any] = [
                    "id": "file_ant_xlsx_123",
                    "filename": "projects.xlsx",
                    "mime_type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data
                )

            case "/messages":
                let body = try XCTUnwrap(requestBodyData(request))
                let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
                let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
                let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])

                let uploadBlock = try XCTUnwrap(content.first)
                XCTAssertEqual(uploadBlock["type"] as? String, "container_upload")
                XCTAssertEqual(uploadBlock["file_id"] as? String, "file_ant_xlsx_123")
                XCTAssertFalse(content.contains { ($0["type"] as? String) == "text" })

                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("data: [DONE]\n\n".utf8)
                )

            default:
                XCTFail("Unexpected request: \(request.url?.absoluteString ?? "<nil>")")
                return (
                    HTTPURLResponse(url: request.url ?? URL(string: "https://example.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            }
        }

        let adapter = AnthropicAdapter(
            providerConfig: providerConfig,
            apiKey: "test-key",
            networkManager: networkManager
        )

        let xlsx = FileContent(
            mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            filename: "projects.xlsx",
            data: Data([0x50, 0x4B, 0x03, 0x04]),
            url: nil,
            extractedText: "sheet"
        )

        let controls = GenerationControls(
            codeExecution: CodeExecutionControls(enabled: true)
        )

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.file(xlsx)])],
            modelID: "claude-haiku-4-5-20251001",
            controls: controls,
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
        XCTAssertEqual(uploadCount, 1)
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
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
