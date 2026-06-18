import XCTest
import Foundation
@testable import Jin

final class NetworkDebugLoggerTests: XCTestCase {
    private var previousAppSupportRoot: String?
    private var temporaryRoot: URL?

    override func setUpWithError() throws {
        try super.setUpWithError()
        previousAppSupportRoot = ProcessInfo.processInfo.environment["JIN_APP_SUPPORT_ROOT"]
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("jin-network-debug-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: try XCTUnwrap(temporaryRoot), withIntermediateDirectories: true)
        setenv("JIN_APP_SUPPORT_ROOT", try XCTUnwrap(temporaryRoot).path, 1)
        UserDefaults.standard.set(true, forKey: AppPreferenceKeys.networkDebugLoggingEnabled)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppPreferenceKeys.networkDebugLoggingEnabled)

        if let previousAppSupportRoot {
            setenv("JIN_APP_SUPPORT_ROOT", previousAppSupportRoot, 1)
        } else {
            unsetenv("JIN_APP_SUPPORT_ROOT")
        }

        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        temporaryRoot = nil
        previousAppSupportRoot = nil
        super.tearDown()
    }

    func testHTTPTraceRedactsSecretsAndOmitsBodies() async throws {
        try await NetworkDebugLogger.shared.clearLogs()

        var request = URLRequest(url: URL(string: "https://user:password@example.com/v1/chat?token=url-secret&query=visible")!)
        request.httpMethod = "POST"
        request.addValue("Bearer sk-request-secret", forHTTPHeaderField: "Authorization")
        request.addValue("session=response-secret", forHTTPHeaderField: "Cookie")
        request.addValue("goog-key-secret", forHTTPHeaderField: "x-goog-api-key")
        request.addValue("brave-token-secret", forHTTPHeaderField: "X-Subscription-Token")
        request.addValue("eleven-key-secret", forHTTPHeaderField: "xi-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"prompt":"PRIVATE_CHAT_PROMPT","api_key":"body-secret"}"#.utf8)

        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: URL(string: "https://example.com/v1/chat?api_key=response-url-secret&query=visible")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/json",
                    "Set-Cookie": "server=response-cookie-secret",
                    "openai-request-id": "req_123"
                ]
            )
        )

        await NetworkDebugLogScope.$current.withValue(NetworkDebugLogContext(conversationID: "conversation")) {
            let requestID = await NetworkDebugLogger.shared.beginRequest(request, mode: "data")
            await NetworkDebugLogger.shared.endRequest(
                requestID: requestID,
                response: response,
                responseBody: Data(#"{"output":"PRIVATE_MODEL_RESPONSE"}"#.utf8),
                responseBodyTruncated: false,
                error: nil
            )
        }

        let trace = try readOnlyTraceFile()
        XCTAssertTrue(trace.contains("<redacted>"))
        XCTAssertTrue(trace.contains("<body omitted from network trace>"))
        XCTAssertTrue(trace.contains("query=visible"))
        XCTAssertTrue(trace.contains("req_123"))
        XCTAssertFalse(trace.contains("sk-request-secret"))
        XCTAssertFalse(trace.contains("response-secret"))
        XCTAssertFalse(trace.contains("url-secret"))
        XCTAssertFalse(trace.contains("response-url-secret"))
        XCTAssertFalse(trace.contains("PRIVATE_CHAT_PROMPT"))
        XCTAssertFalse(trace.contains("body-secret"))
        XCTAssertFalse(trace.contains("response-cookie-secret"))
        XCTAssertFalse(trace.contains("PRIVATE_MODEL_RESPONSE"))
        XCTAssertFalse(trace.contains("goog-key-secret"))
        XCTAssertFalse(trace.contains("brave-token-secret"))
        XCTAssertFalse(trace.contains("eleven-key-secret"))
    }

    func testWebSocketTraceRedactsHeadersAndOmitsFrameBodies() async throws {
        try await NetworkDebugLogger.shared.clearLogs()

        await NetworkDebugLogScope.$current.withValue(NetworkDebugLogContext(conversationID: "conversation")) {
            let sessionID = await NetworkDebugLogger.shared.beginWebSocketSession(
                url: URL(string: "wss://user:password@example.com/realtime?token=socket-url-secret")!,
                headers: ["Authorization": "Bearer socket-secret", "Content-Type": "application/json"]
            )
            await NetworkDebugLogger.shared.logWebSocketSend(
                sessionID: sessionID,
                message: #"{"input":"PRIVATE_SOCKET_PROMPT"}"#
            )
            await NetworkDebugLogger.shared.logWebSocketReceive(
                sessionID: sessionID,
                message: #"{"output":"PRIVATE_SOCKET_RESPONSE"}"#
            )
            await NetworkDebugLogger.shared.endWebSocketSession(sessionID: sessionID, error: nil)
        }

        let trace = try readOnlyTraceFile()
        XCTAssertTrue(trace.contains("<redacted>"))
        XCTAssertTrue(trace.contains("<body omitted from network trace>"))
        XCTAssertFalse(trace.contains("socket-secret"))
        XCTAssertFalse(trace.contains("socket-url-secret"))
        XCTAssertFalse(trace.contains("PRIVATE_SOCKET_PROMPT"))
        XCTAssertFalse(trace.contains("PRIVATE_SOCKET_RESPONSE"))
    }

    private func readOnlyTraceFile() throws -> String {
        let root = NetworkDebugLogger.logRootDirectoryURL
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }
        XCTAssertEqual(files.count, 1)
        return try String(contentsOf: try XCTUnwrap(files.first), encoding: .utf8)
    }
}
