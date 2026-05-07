import XCTest
@testable import Jin

@MainActor
final class CodexAppServerFormSupportTests: XCTestCase {
    func testListenURLFallsBackToCodexDefaultWhenBaseURLIsBlank() {
        XCTAssertEqual(
            CodexAppServerFormSupport.listenURL(baseURL: nil),
            ProviderType.codexAppServer.defaultBaseURL
        )
        XCTAssertEqual(
            CodexAppServerFormSupport.listenURL(baseURL: " \n "),
            ProviderType.codexAppServer.defaultBaseURL
        )
        XCTAssertEqual(
            CodexAppServerFormSupport.listenURL(baseURL: " wss://localhost:4501 "),
            "wss://localhost:4501"
        )
    }

    func testListenURLValidationAllowsOnlyLocalWebSocketAddresses() {
        XCTAssertNil(CodexAppServerFormSupport.listenURLValidationError("ws://127.0.0.1:4500"))
        XCTAssertNil(CodexAppServerFormSupport.listenURLValidationError("wss://localhost:4500"))
        XCTAssertNil(CodexAppServerFormSupport.listenURLValidationError("ws://[::1]:4500"))

        XCTAssertEqual(
            CodexAppServerFormSupport.listenURLValidationError("http://127.0.0.1:4500"),
            "Base URL must be a valid ws:// or wss:// listen address to launch app-server."
        )
        XCTAssertEqual(
            CodexAppServerFormSupport.listenURLValidationError("ws://example.com:4500"),
            "In-app app-server launch only supports localhost listen addresses."
        )
    }

    func testStatusPresentationMatchesServerStatusCopyAndTone() {
        XCTAssertEqual(
            CodexAppServerFormSupport.statusPresentation(
                status: .stopped,
                listenURL: "ws://127.0.0.1:4500",
                validationError: nil
            ),
            .init(
                label: "Server stopped",
                tone: .neutral,
                message: "Ready to launch `codex app-server --listen ws://127.0.0.1:4500`."
            )
        )

        XCTAssertEqual(
            CodexAppServerFormSupport.statusPresentation(
                status: .starting,
                listenURL: "ws://127.0.0.1:4500",
                validationError: nil
            ),
            .init(
                label: "Server starting",
                tone: .warning,
                message: "Starting `codex app-server --listen ws://127.0.0.1:4500`..."
            )
        )

        XCTAssertEqual(
            CodexAppServerFormSupport.statusPresentation(
                status: .running(pid: 1234, listenURL: "ws://127.0.0.1:4501"),
                listenURL: "ws://127.0.0.1:4500",
                validationError: nil
            ),
            .init(
                label: "Server running",
                tone: .success,
                message: "`codex app-server` is running (pid 1234) on ws://127.0.0.1:4501"
            )
        )

        XCTAssertEqual(
            CodexAppServerFormSupport.statusPresentation(
                status: .failed("launch failed"),
                listenURL: "ws://127.0.0.1:4500",
                validationError: nil
            ),
            .init(label: "Server failed", tone: .failure, message: "launch failed")
        )
    }

    func testValidationMessageOverridesStatusMessage() {
        let presentation = CodexAppServerFormSupport.statusPresentation(
            status: .running(pid: 1234, listenURL: "ws://127.0.0.1:4500"),
            listenURL: "ws://example.com:4500",
            validationError: "In-app app-server launch only supports localhost listen addresses."
        )

        XCTAssertEqual(presentation.label, "Server running")
        XCTAssertEqual(presentation.tone, .success)
        XCTAssertEqual(
            presentation.message,
            "In-app app-server launch only supports localhost listen addresses."
        )
    }

    func testButtonStateMatchesLaunchAndShutdownEligibility() {
        XCTAssertEqual(
            CodexAppServerFormSupport.buttonState(
                status: .stopped,
                hasManagedProcesses: false,
                validationError: nil
            ),
            .init(startDisabled: false, stopDisabled: true, forceStopDisabled: true)
        )
        XCTAssertEqual(
            CodexAppServerFormSupport.buttonState(
                status: .starting,
                hasManagedProcesses: true,
                validationError: nil
            ),
            .init(startDisabled: true, stopDisabled: false, forceStopDisabled: false)
        )
        XCTAssertEqual(
            CodexAppServerFormSupport.buttonState(
                status: .running(pid: 1, listenURL: "ws://127.0.0.1:4500"),
                hasManagedProcesses: true,
                validationError: nil
            ),
            .init(startDisabled: true, stopDisabled: false, forceStopDisabled: false)
        )
        XCTAssertEqual(
            CodexAppServerFormSupport.buttonState(
                status: .failed("bad"),
                hasManagedProcesses: false,
                validationError: nil
            ),
            .init(startDisabled: false, stopDisabled: true, forceStopDisabled: false)
        )
        XCTAssertEqual(
            CodexAppServerFormSupport.buttonState(
                status: .stopped,
                hasManagedProcesses: true,
                validationError: "invalid"
            ),
            .init(startDisabled: true, stopDisabled: true, forceStopDisabled: false)
        )
    }

    func testLingeringProcessWarningOnlyAppearsWhenStoppedWithManagedProcesses() {
        XCTAssertEqual(
            CodexAppServerFormSupport.lingeringProcessWarning(
                status: .stopped,
                managedProcessCount: 2
            ),
            "Detected 2 Jin-managed Codex app-server process(es) still running. Use Force Stop to clean them up."
        )
        XCTAssertNil(
            CodexAppServerFormSupport.lingeringProcessWarning(
                status: .running(pid: 1, listenURL: "ws://127.0.0.1:4500"),
                managedProcessCount: 2
            )
        )
        XCTAssertNil(
            CodexAppServerFormSupport.lingeringProcessWarning(
                status: .stopped,
                managedProcessCount: 0
            )
        )
    }

    func testAuthStatusPresentationMatchesCurrentCopyAndTone() {
        XCTAssertEqual(
            CodexAppServerFormSupport.authStatusPresentation(status: .idle, account: nil),
            .init(
                label: "Not checked",
                tone: .neutral,
                message: "Use Connect ChatGPT to open browser login."
            )
        )
        XCTAssertEqual(
            CodexAppServerFormSupport.authStatusPresentation(status: .working, account: nil),
            .init(
                label: "Working",
                tone: .warning,
                message: "Waiting for ChatGPT account authorization..."
            )
        )
        XCTAssertEqual(
            CodexAppServerFormSupport.authStatusPresentation(
                status: .failure("Login failed"),
                account: nil
            ),
            .init(label: "Failed", tone: .neutral, message: "Login failed")
        )
    }

    func testAuthStatusPresentationPrefersNameEmailThenModeForConnectedAccounts() {
        XCTAssertEqual(
            CodexAppServerFormSupport.authStatusPresentation(
                status: .connected,
                account: account(name: " Ada ", email: " ada@example.com ", authMode: "chatgpt")
            ),
            .init(
                label: "Connected",
                tone: .success,
                message: "Logged in as Ada (ada@example.com)."
            )
        )
        XCTAssertEqual(
            CodexAppServerFormSupport.authStatusPresentation(
                status: .connected,
                account: account(name: " ", email: " ada@example.com ", authMode: "chatgpt")
            ).message,
            "Logged in as ada@example.com."
        )
        XCTAssertEqual(
            CodexAppServerFormSupport.authStatusPresentation(
                status: .connected,
                account: account(name: nil, email: nil, authMode: " chatgpt ")
            ).message,
            "Account is authenticated via chatgpt."
        )
        XCTAssertEqual(
            CodexAppServerFormSupport.authStatusPresentation(status: .connected, account: nil).message,
            "Account is authenticated."
        )
    }

    func testAuthButtonStateDisablesActionsWhileWorkingAndRequiresAuthenticationForLogout() {
        XCTAssertEqual(
            CodexAppServerFormSupport.authButtonState(status: .working, isAuthenticated: true),
            .init(connectDisabled: true, refreshDisabled: true, logoutDisabled: true)
        )
        XCTAssertEqual(
            CodexAppServerFormSupport.authButtonState(status: .connected, isAuthenticated: true),
            .init(connectDisabled: false, refreshDisabled: false, logoutDisabled: false)
        )
        XCTAssertEqual(
            CodexAppServerFormSupport.authButtonState(status: .idle, isAuthenticated: false),
            .init(connectDisabled: false, refreshDisabled: false, logoutDisabled: true)
        )
    }

    func testRateLimitTextIncludesOnlyAvailableDetails() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(
            from: DateComponents(
                timeZone: TimeZone(secondsFromGMT: 0),
                year: 2026,
                month: 5,
                day: 5,
                hour: 12,
                minute: 34
            )
        )!

        XCTAssertEqual(
            CodexAppServerFormSupport.rateLimitText(
                CodexAppServerAdapter.RateLimitStatus(
                    name: "primary",
                    usedPercentage: nil,
                    windowMinutes: nil,
                    resetsAt: nil
                )
            ),
            "Rate limit: primary"
        )
        let detailedText = CodexAppServerFormSupport.rateLimitText(
            CodexAppServerAdapter.RateLimitStatus(
                name: "primary",
                usedPercentage: 12,
                windowMinutes: 60,
                resetsAt: date
            )
        )
        XCTAssertTrue(detailedText.hasPrefix("Rate limit: primary · 12% used · window 60m · resets "))
    }

    func testCanUseAuthenticationModeMatchesCredentialRequirements() {
        XCTAssertTrue(
            CodexAppServerFormSupport.canUseAuthenticationMode(
                mode: .apiKey,
                apiKey: " token ",
                status: .idle,
                isAuthenticated: false,
                hasLocalKey: false
            )
        )
        XCTAssertFalse(
            CodexAppServerFormSupport.canUseAuthenticationMode(
                mode: .apiKey,
                apiKey: " ",
                status: .idle,
                isAuthenticated: true,
                hasLocalKey: true
            )
        )
        XCTAssertTrue(
            CodexAppServerFormSupport.canUseAuthenticationMode(
                mode: .chatGPT,
                apiKey: "",
                status: .connected,
                isAuthenticated: true,
                hasLocalKey: false
            )
        )
        XCTAssertFalse(
            CodexAppServerFormSupport.canUseAuthenticationMode(
                mode: .chatGPT,
                apiKey: "",
                status: .idle,
                isAuthenticated: true,
                hasLocalKey: false
            )
        )
        XCTAssertTrue(
            CodexAppServerFormSupport.canUseAuthenticationMode(
                mode: .localCodex,
                apiKey: "",
                status: .idle,
                isAuthenticated: false,
                hasLocalKey: true
            )
        )
    }

    func testLocalAuthPresentationReflectsLocalKeyAvailability() {
        XCTAssertEqual(
            CodexAppServerFormSupport.localAuthPresentation(
                hasLocalKey: true,
                authPath: "/Users/example/.codex/auth.json"
            ),
            .init(
                label: "Local key available",
                tone: .success,
                message: "Reusing the API key stored by your local Codex CLI in `/Users/example/.codex/auth.json`.",
                missingKeyMessage: nil
            )
        )
        XCTAssertEqual(
            CodexAppServerFormSupport.localAuthPresentation(
                hasLocalKey: false,
                authPath: "/Users/example/.codex/auth.json"
            ),
            .init(
                label: "No local key",
                tone: .neutral,
                message: "Reusing the API key stored by your local Codex CLI in `/Users/example/.codex/auth.json`.",
                missingKeyMessage: "No `OPENAI_API_KEY` found yet. Run `codex login` or update your local auth file first."
            )
        )
    }

    private func account(
        name: String?,
        email: String?,
        authMode: String?
    ) -> CodexAppServerAdapter.AccountStatus {
        CodexAppServerAdapter.AccountStatus(
            isAuthenticated: true,
            requiresOpenAIAuth: false,
            authMode: authMode,
            accountType: nil,
            displayName: name,
            email: email
        )
    }
}
