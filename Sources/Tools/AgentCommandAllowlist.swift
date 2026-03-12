import Foundation

enum AgentCommandAllowlist {
    static let defaultSafePrefixes: [String] = [
        "ls", "cat", "head", "tail", "wc", "file", "which", "pwd", "echo",
        "rg", "grep", "find", "tree", "stat", "du", "df", "env", "printenv",
        "git status", "git log", "git diff", "git show", "git branch", "git remote",
        "swift build", "swift test", "swift package",
        "xcodebuild -showBuildSettings",
        "man", "less", "sort", "uniq", "cut", "tr", "sed", "awk",
        "date", "whoami", "hostname", "uname",
        "open", "pbcopy", "pbpaste"
    ]

    static func isCommandAllowed(
        _ command: String,
        allowedPrefixes: [String],
        sessionPrefixes: [String] = []
    ) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // For piped commands, check the first command in the pipeline
        let firstCommand = extractFirstPipelineCommand(trimmed)
        let allPrefixes = allowedPrefixes + sessionPrefixes

        for prefix in allPrefixes {
            if matchesPrefix(command: firstCommand, prefix: prefix) {
                return true
            }
        }

        return false
    }

    private static func extractFirstPipelineCommand(_ command: String) -> String {
        // Split on pipe, but not inside quotes
        var depth = 0
        var inSingleQuote = false
        var inDoubleQuote = false

        for (index, char) in command.enumerated() {
            switch char {
            case "'" where !inDoubleQuote:
                inSingleQuote.toggle()
            case "\"" where !inSingleQuote:
                inDoubleQuote.toggle()
            case "(" where !inSingleQuote && !inDoubleQuote:
                depth += 1
            case ")" where !inSingleQuote && !inDoubleQuote:
                depth = max(0, depth - 1)
            case "|" where !inSingleQuote && !inDoubleQuote && depth == 0:
                let firstPart = String(command[command.startIndex..<command.index(command.startIndex, offsetBy: index)])
                return firstPart.trimmingCharacters(in: .whitespacesAndNewlines)
            default:
                break
            }
        }

        return command.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matchesPrefix(command: String, prefix: String) -> Bool {
        let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedPrefix.isEmpty else { return false }

        // Exact match
        if normalizedCommand == normalizedPrefix {
            return true
        }

        // Prefix match: command starts with prefix followed by whitespace or end
        if normalizedCommand.hasPrefix(normalizedPrefix) {
            let afterPrefix = normalizedCommand.index(normalizedCommand.startIndex, offsetBy: normalizedPrefix.count)
            if afterPrefix == normalizedCommand.endIndex {
                return true
            }
            let nextChar = normalizedCommand[afterPrefix]
            return nextChar == " " || nextChar == "\t" || nextChar == "\n"
        }

        return false
    }
}
