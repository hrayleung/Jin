import Foundation

actor GitHubCLIAuthBridge {
    enum Error: LocalizedError {
        case executableNotFound
        case commandFailed(message: String)
        case emptyToken

        var errorDescription: String? {
            switch self {
            case .executableNotFound:
                return "GitHub CLI (`gh`) is not installed or not available in Jin's PATH."
            case .commandFailed(let message):
                return message
            case .emptyToken:
                return "GitHub CLI did not return an authentication token."
            }
        }
    }

    func importToken() async throws -> String {
        if let token = try? await currentToken(), !token.isEmpty {
            return token
        }

        _ = try await run([
            "auth", "login",
            "--web",
            "--hostname", "github.com",
            "--git-protocol", "https",
            "--skip-ssh-key"
        ])

        let token = try await currentToken()
        guard !token.isEmpty else {
            throw Error.emptyToken
        }
        return token
    }

    func currentToken() async throws -> String {
        let output = try await run(["auth", "token", "--hostname", "github.com"])
        let token = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw Error.emptyToken
        }
        return token
    }

    func isAvailable() -> Bool {
        executableURL() != nil
    }

    private func run(_ arguments: [String]) async throws -> String {
        guard let executableURL = executableURL() else {
            throw Error.executableNotFound
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                    return
                }

                let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallback = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(throwing: Error.commandFailed(message: message.isEmpty ? fallback : message))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: Error.commandFailed(message: error.localizedDescription))
            }
        }
    }

    private func executableURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let path = environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for component in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(component)).appendingPathComponent("gh")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
