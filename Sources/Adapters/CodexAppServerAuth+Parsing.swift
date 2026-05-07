import Foundation

extension CodexAppServerAdapter {
    func parseAccountStatus(from result: JSONValue) throws -> AccountStatus {
        guard let object = result.objectValue else {
            throw LLMError.decodingError(message: "Codex account/read returned unexpected payload.")
        }

        let authMode = object.string(at: ["authMode"])
        let requiresOpenAIAuth = object.bool(at: ["requiresOpenaiAuth"])
            ?? object.bool(at: ["requiresOpenAIAuth"])
            ?? false
        let account = object.object(at: ["account"])

        let accountType = account?.string(at: ["type"]) ?? authMode
        let displayName = account?.string(at: ["name"])
            ?? account?.string(at: ["displayName"])
            ?? account?.string(at: ["username"])
        let email = account?.string(at: ["email"])

        return AccountStatus(
            isAuthenticated: account != nil,
            requiresOpenAIAuth: requiresOpenAIAuth,
            authMode: authMode,
            accountType: accountType,
            displayName: displayName,
            email: email
        )
    }

    func parsePrimaryRateLimit(from result: JSONValue) -> RateLimitStatus? {
        guard let object = result.objectValue else { return nil }

        let rootRateLimit = object.object(at: ["rateLimit"])
            ?? object.object(at: ["primary"])
            ?? object.object(at: ["rateLimits", "primary"])
        let arrayRateLimit = object.array(at: ["rateLimits"])?.first?.objectValue
            ?? object.array(at: ["limits"])?.first?.objectValue
        guard let rateLimit = rootRateLimit ?? arrayRateLimit else {
            return nil
        }

        let name = rateLimit.string(at: ["name"])
            ?? rateLimit.string(at: ["id"])
            ?? "primary"
        let usedPercentage = rateLimit.double(at: ["usedPercentage"])
            ?? rateLimit.double(at: ["usedPercent"])
            ?? rateLimit.double(at: ["percentUsed"])
        let windowMinutes = rateLimit.int(at: ["windowMinutes"])
            ?? rateLimit.int(at: ["windowMins"])
        let resetsAt = parseDate(rateLimit.string(at: ["resetsAt"])
            ?? rateLimit.string(at: ["resetAt"])
            ?? rateLimit.string(at: ["resetTime"]))

        return RateLimitStatus(
            name: name,
            usedPercentage: usedPercentage,
            windowMinutes: windowMinutes,
            resetsAt: resetsAt
        )
    }

    func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatter.date(from: raw) {
            return parsed
        }

        let fallback = ISO8601DateFormatter()
        return fallback.date(from: raw)
    }
}
