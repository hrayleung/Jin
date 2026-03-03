import XCTest
@testable import Jin

final class CodexAppServerAdapterConnectionGuidanceTests: XCTestCase {
    func testCodexConnectivityGuidanceMessageForConnectionRefused() throws {
        let endpoint = try XCTUnwrap(URL(string: "ws://127.0.0.1:4500"))
        let error = LLMError.networkError(
            underlying: NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(ECONNREFUSED),
                userInfo: [NSLocalizedDescriptionKey: "Connection refused"]
            )
        )

        let message = CodexAppServerAdapter.codexConnectivityGuidanceMessage(
            for: error,
            endpoint: endpoint
        )

        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("Codex App Server") == true)
        XCTAssertTrue(message?.contains("codex app-server --listen ws://127.0.0.1:4500") == true)
    }

    func testRemapCodexConnectivityErrorReturnsProviderErrorWithGuidance() throws {
        let endpoint = try XCTUnwrap(URL(string: "ws://127.0.0.1:4500"))
        let original = LLMError.networkError(
            underlying: NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(ETIMEDOUT),
                userInfo: [NSLocalizedDescriptionKey: "Connection timed out"]
            )
        )

        let remapped = CodexAppServerAdapter.remapCodexConnectivityError(original, endpoint: endpoint)

        guard case let llmError as LLMError = remapped else {
            XCTFail("Expected LLMError after remap")
            return
        }

        guard case let .providerError(code, message) = llmError else {
            XCTFail("Expected providerError after remap")
            return
        }

        XCTAssertEqual(code, "codex_server_unavailable")
        XCTAssertTrue(message.contains("ws://127.0.0.1:4500"))
    }

    func testRemapCodexConnectivityErrorDoesNotRewriteAuthenticationErrors() throws {
        let endpoint = try XCTUnwrap(URL(string: "ws://127.0.0.1:4500"))
        let original = LLMError.authenticationFailed(message: "bad key")

        let remapped = CodexAppServerAdapter.remapCodexConnectivityError(original, endpoint: endpoint)

        guard case let llmError as LLMError = remapped else {
            XCTFail("Expected LLMError after remap")
            return
        }

        guard case let .authenticationFailed(message) = llmError else {
            XCTFail("Expected authenticationFailed to remain unchanged")
            return
        }

        XCTAssertEqual(message, "bad key")
    }
}
