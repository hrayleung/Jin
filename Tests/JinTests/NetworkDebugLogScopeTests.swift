import XCTest
@testable import Jin

final class NetworkDebugLogScopeTests: XCTestCase {
    func testNetworkDebugLogContextTrimsConversationID() {
        let context = NetworkDebugLogContext(conversationID: " conversation\n")
        XCTAssertEqual(context.jsonObject, ["conversation_id": "conversation"])
    }

    func testNetworkDebugLogContextDropsBlankIdentifier() {
        let context = NetworkDebugLogContext(conversationID: " \t ")
        XCTAssertEqual(context.jsonObject, [:])
    }
}

final class NetworkDebugLoggerSecurityTests: XCTestCase {
    func testWebSocketTraceRedactsHeadersAndFrameBodies() async throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("jin-network-debug-logger-tests-")
            .appendingPathComponent(UUID().uuidString)
        let previousRoot = ProcessInfo.processInfo.environment["JIN_APP_SUPPORT_ROOT"]
        let previousEnabled = UserDefaults.standard.object(forKey: AppPreferenceKeys.networkDebugLoggingEnabled)

        setenv("JIN_APP_SUPPORT_ROOT", temporaryRoot.path, 1)
        UserDefaults.standard.set(true, forKey: AppPreferenceKeys.networkDebugLoggingEnabled)
        defer {
            if let previousRoot {
                setenv("JIN_APP_SUPPORT_ROOT", previousRoot, 1)
            } else {
                unsetenv("JIN_APP_SUPPORT_ROOT")
            }
            if let previousEnabled {
                UserDefaults.standard.set(previousEnabled, forKey: AppPreferenceKeys.networkDebugLoggingEnabled)
            } else {
                UserDefaults.standard.removeObject(forKey: AppPreferenceKeys.networkDebugLoggingEnabled)
            }
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        try await NetworkDebugLogger.shared.clearLogs()

        try await NetworkDebugLogScope.$current.withValue(NetworkDebugLogContext(conversationID: "security-test")) {
            let sessionID = await NetworkDebugLogger.shared.beginWebSocketSession(
                url: URL(string: "wss://api.openai.example/v1/responses")!,
                headers: [
                    "Authorization": "Bearer sk-test-plaintext-key",
                    "OpenAI-Beta": "responses=v1"
                ]
            )

            await NetworkDebugLogger.shared.logWebSocketSend(
                sessionID: sessionID,
                message: #"{"type":"response.create","response":{"input":[{"content":"PRIVATE_PROMPT_123","file_data":"data:text/plain;base64,U0VDUkVUX0FUVEFDSE1FTlQ="}]}}"#
            )
            await NetworkDebugLogger.shared.logWebSocketReceive(
                sessionID: sessionID,
                message: #"{"type":"response.output_text.delta","delta":"PRIVATE_RESPONSE_456"}"#
            )
            await NetworkDebugLogger.shared.endWebSocketSession(sessionID: sessionID, error: nil)
        }

        let traceRoot = try AppDataLocations.networkTraceDirectoryURL()
        let traceFiles = try FileManager.default.contentsOfDirectory(
            at: traceRoot,
            includingPropertiesForKeys: nil
        ).flatMap { dayURL in
            try FileManager.default.contentsOfDirectory(at: dayURL, includingPropertiesForKeys: nil)
        }
        XCTAssertEqual(traceFiles.count, 1)

        let data = try Data(contentsOf: traceFiles[0])
        let traceText = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(traceText.contains("sk-test-plaintext-key"))
        XCTAssertFalse(traceText.contains("PRIVATE_PROMPT_123"))
        XCTAssertFalse(traceText.contains("U0VDUkVUX0FUVEFDSE1FTlQ="))
        XCTAssertFalse(traceText.contains("PRIVATE_RESPONSE_456"))

        let record = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let connection = try XCTUnwrap(record["connection"] as? [String: Any])
        let headers = try XCTUnwrap(connection["headers"] as? [String: String])
        XCTAssertEqual(headers["Authorization"], "<redacted>")
        XCTAssertEqual(headers["OpenAI-Beta"], "responses=v1")

        let frames = try XCTUnwrap(record["frames"] as? [[String: Any]])
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0]["direction"] as? String, "send")
        XCTAssertEqual(frames[0]["event_type"] as? String, "response.create")
        XCTAssertEqual(frames[0]["body_redacted"] as? Bool, true)
        XCTAssertNil(frames[0]["body"])
        XCTAssertEqual(frames[1]["direction"] as? String, "receive")
        XCTAssertEqual(frames[1]["event_type"] as? String, "response.output_text.delta")
        XCTAssertEqual(frames[1]["body_redacted"] as? Bool, true)
        XCTAssertNil(frames[1]["body"])
    }
}
