import Foundation

extension CodexAppServerFormSupport {
    static func authStatusPresentation(
        status: ProviderConfigFormView.CodexAuthStatus,
        account: CodexAppServerAdapter.AccountStatus?
    ) -> StatusPresentation {
        StatusPresentation(
            label: authStatusLabel(for: status),
            tone: authStatusTone(for: status),
            message: authStatusMessage(for: status, account: account)
        )
    }

    static func authStatusLabel(for status: ProviderConfigFormView.CodexAuthStatus) -> String {
        switch status {
        case .idle:
            return "Not checked"
        case .working:
            return "Working"
        case .connected:
            return "Connected"
        case .failure:
            return "Failed"
        }
    }

    static func authStatusTone(for status: ProviderConfigFormView.CodexAuthStatus) -> StatusTone {
        switch status {
        case .connected:
            return .success
        case .working:
            return .warning
        case .idle, .failure:
            return .neutral
        }
    }

    static func authStatusMessage(
        for status: ProviderConfigFormView.CodexAuthStatus,
        account: CodexAppServerAdapter.AccountStatus?
    ) -> String {
        switch status {
        case .idle:
            return "Use Connect ChatGPT to open browser login."
        case .working:
            return "Waiting for ChatGPT account authorization..."
        case .connected:
            return authenticatedAccountMessage(account)
        case .failure(let message):
            return message
        }
    }

    static func authButtonState(
        status: ProviderConfigFormView.CodexAuthStatus,
        isAuthenticated: Bool
    ) -> AuthButtonState {
        let isWorking = status == .working
        return AuthButtonState(
            connectDisabled: isWorking,
            refreshDisabled: isWorking,
            logoutDisabled: isWorking || !isAuthenticated
        )
    }

    static func rateLimitText(_ rateLimit: CodexAppServerAdapter.RateLimitStatus) -> String {
        rateLimitSegments(rateLimit).joined(separator: " · ")
    }

    static func canUseAuthenticationMode(
        mode: ProviderConfigFormView.CodexAuthMode,
        apiKey: String,
        status: ProviderConfigFormView.CodexAuthStatus,
        isAuthenticated: Bool,
        hasLocalKey: Bool
    ) -> Bool {
        switch mode {
        case .apiKey:
            return apiKey.trimmedNonEmpty != nil
        case .chatGPT:
            return isAuthenticated && status == .connected
        case .localCodex:
            return hasLocalKey
        }
    }

    static func localAuthPresentation(
        hasLocalKey: Bool,
        authPath: String
    ) -> LocalAuthPresentation {
        LocalAuthPresentation(
            label: hasLocalKey ? "Local key available" : "No local key",
            tone: hasLocalKey ? .success : .neutral,
            message: "Reusing the API key stored by your local Codex CLI in `\(authPath)`.",
            missingKeyMessage: hasLocalKey
                ? nil
                : "No `OPENAI_API_KEY` found yet. Run `codex login` or update your local auth file first."
        )
    }

    private static func authenticatedAccountMessage(_ account: CodexAppServerAdapter.AccountStatus?) -> String {
        let name = account?.displayName?.trimmedNonEmpty
        let email = account?.email?.trimmedNonEmpty
        if let name, let email {
            return "Logged in as \(name) (\(email))."
        }
        if let email {
            return "Logged in as \(email)."
        }

        if let mode = account?.authMode?.trimmedNonEmpty {
            return "Account is authenticated via \(mode)."
        }
        return "Account is authenticated."
    }

    private static func rateLimitSegments(_ rateLimit: CodexAppServerAdapter.RateLimitStatus) -> [String] {
        [
            "Rate limit: \(rateLimit.name)",
            rateLimitUsedPercentageText(rateLimit.usedPercentage),
            rateLimitWindowText(rateLimit.windowMinutes),
            rateLimitResetText(rateLimit.resetsAt)
        ].compactMap { $0 }
    }

    private static func rateLimitUsedPercentageText(_ usedPercentage: Double?) -> String? {
        guard let usedPercentage else { return nil }
        let formatted = usedPercentage.formatted(.number.precision(.fractionLength(0...2)))
        return "\(formatted)% used"
    }

    private static func rateLimitWindowText(_ windowMinutes: Int?) -> String? {
        guard let windowMinutes else { return nil }
        return "window \(windowMinutes)m"
    }

    private static func rateLimitResetText(_ resetsAt: Date?) -> String? {
        guard let resetsAt else { return nil }
        return "resets \(resetsAt.formatted(date: .omitted, time: .shortened))"
    }
}
