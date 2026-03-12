import Foundation

enum AgentFileOperations {

    enum FileOperationError: LocalizedError {
        case fileNotFound(String)
        case notAFile(String)
        case readFailed(String)
        case writeFailed(String)
        case editNotFound(String, String)
        case editAmbiguous(String, String, Int)
        case directoryCreationFailed(String)
        case invalidPattern(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let path):
                return "File not found: \(path)"
            case .notAFile(let path):
                return "Path is not a file: \(path)"
            case .readFailed(let path):
                return "Failed to read file: \(path)"
            case .writeFailed(let path):
                return "Failed to write file: \(path)"
            case .editNotFound(let path, let text):
                let preview = String(text.prefix(100))
                return "Text not found in \(path): \"\(preview)\""
            case .editAmbiguous(let path, let text, let count):
                let preview = String(text.prefix(100))
                return "Text found \(count) times in \(path) (must be unique): \"\(preview)\""
            case .directoryCreationFailed(let path):
                return "Failed to create directory: \(path)"
            case .invalidPattern(let pattern):
                return "Invalid pattern: \(pattern)"
            }
        }
    }

    // MARK: - Read File

    static func readFile(
        path: String,
        offset: Int? = nil,
        limit: Int? = nil,
        workingDirectory: String? = nil
    ) throws -> String {
        let resolvedPath = resolvePath(path, workingDirectory: workingDirectory)
        let fm = FileManager.default

        guard fm.fileExists(atPath: resolvedPath) else {
            throw FileOperationError.fileNotFound(resolvedPath)
        }

        var isDir: ObjCBool = false
        fm.fileExists(atPath: resolvedPath, isDirectory: &isDir)
        if isDir.boolValue {
            throw FileOperationError.notAFile(resolvedPath)
        }

        guard let content = fm.contents(atPath: resolvedPath),
              let text = String(data: content, encoding: .utf8) else {
            throw FileOperationError.readFailed(resolvedPath)
        }

        let lines = text.components(separatedBy: "\n")
        let startLine = max(0, (offset ?? 1) - 1)
        let endLine: Int
        if let limit {
            endLine = min(lines.count, startLine + limit)
        } else {
            endLine = lines.count
        }

        guard startLine < lines.count else {
            return "(offset \(startLine + 1) is beyond end of file, which has \(lines.count) lines)"
        }

        let selectedLines = lines[startLine..<endLine]
        let numberedLines = selectedLines.enumerated().map { index, line in
            let lineNumber = startLine + index + 1
            return String(format: "%6d\t%@", lineNumber, line)
        }

        var result = numberedLines.joined(separator: "\n")
        if endLine < lines.count {
            result += "\n\n(\(lines.count - endLine) more lines not shown)"
        }
        return result
    }

    // MARK: - Write File

    static func writeFile(
        path: String,
        content: String,
        workingDirectory: String? = nil
    ) throws -> String {
        let resolvedPath = resolvePath(path, workingDirectory: workingDirectory)
        let url = URL(fileURLWithPath: resolvedPath)
        let fm = FileManager.default

        let directory = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: directory.path) {
            do {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw FileOperationError.directoryCreationFailed(directory.path)
            }
        }

        guard let data = content.data(using: .utf8) else {
            throw FileOperationError.writeFailed(resolvedPath)
        }

        do {
            try data.write(to: url)
        } catch {
            throw FileOperationError.writeFailed(resolvedPath)
        }

        return "Wrote \(data.count) bytes to \(resolvedPath)"
    }

    // MARK: - Edit File

    static func editFile(
        path: String,
        oldText: String,
        newText: String,
        workingDirectory: String? = nil
    ) throws -> String {
        let resolvedPath = resolvePath(path, workingDirectory: workingDirectory)
        let fm = FileManager.default

        guard fm.fileExists(atPath: resolvedPath) else {
            throw FileOperationError.fileNotFound(resolvedPath)
        }

        guard let data = fm.contents(atPath: resolvedPath),
              let content = String(data: data, encoding: .utf8) else {
            throw FileOperationError.readFailed(resolvedPath)
        }

        let occurrences = content.components(separatedBy: oldText).count - 1
        guard occurrences > 0 else {
            throw FileOperationError.editNotFound(resolvedPath, oldText)
        }
        guard occurrences == 1 else {
            throw FileOperationError.editAmbiguous(resolvedPath, oldText, occurrences)
        }

        let newContent = content.replacingOccurrences(of: oldText, with: newText)

        guard let newData = newContent.data(using: .utf8) else {
            throw FileOperationError.writeFailed(resolvedPath)
        }

        try newData.write(to: URL(fileURLWithPath: resolvedPath))
        return "Edited \(resolvedPath): replaced 1 occurrence (\(oldText.count) chars -> \(newText.count) chars)"
    }

    // MARK: - Glob Search

    static func globSearch(
        pattern: String,
        directory: String? = nil,
        workingDirectory: String? = nil
    ) throws -> String {
        let searchDir = resolvePath(directory ?? ".", workingDirectory: workingDirectory)
        let fm = FileManager.default

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: searchDir, isDirectory: &isDir), isDir.boolValue else {
            throw FileOperationError.fileNotFound(searchDir)
        }

        let searchURL = URL(fileURLWithPath: searchDir)
        let maxResults = 500

        guard let enumerator = fm.enumerator(
            at: searchURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw FileOperationError.readFailed(searchDir)
        }

        var matches: [String] = []
        let globPredicate = buildGlobPredicate(pattern)

        while let fileURL = enumerator.nextObject() as? URL {
            guard matches.count < maxResults else { break }

            let relativePath = fileURL.path.replacingOccurrences(
                of: searchDir.hasSuffix("/") ? searchDir : searchDir + "/",
                with: ""
            )

            if globPredicate(relativePath) || globPredicate(fileURL.lastPathComponent) {
                matches.append(relativePath)
            }
        }

        if matches.isEmpty {
            return "No files matching \"\(pattern)\" found in \(searchDir)"
        }

        var result = matches.joined(separator: "\n")
        if matches.count >= maxResults {
            result += "\n\n(Results limited to \(maxResults) entries)"
        }
        return result
    }

    // MARK: - Grep Search

    static func grepSearch(
        pattern: String,
        path: String? = nil,
        include: String? = nil,
        workingDirectory: String? = nil
    ) throws -> String {
        let searchPath = resolvePath(path ?? ".", workingDirectory: workingDirectory)

        var args = ["-rn"]
        if let include {
            args.append("--include=\(include)")
        }
        args.append(pattern)
        args.append(searchPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let maxBytes = 51_200 // ~50KB
        let output: String

        if data.count > maxBytes {
            let truncated = data.prefix(maxBytes)
            output = (String(data: truncated, encoding: .utf8) ?? "")
                + "\n\n[Output truncated: \(data.count) bytes total, showing first \(maxBytes) bytes]"
        } else {
            output = String(data: data, encoding: .utf8) ?? ""
        }

        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No matches found for \"\(pattern)\" in \(searchPath)"
        }

        return output
    }

    // MARK: - Helpers

    static func resolvePath(_ path: String, workingDirectory: String?) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            return (trimmed as NSString).expandingTildeInPath
        }

        if let cwd = workingDirectory {
            let base = (cwd as NSString).expandingTildeInPath
            return (base as NSString).appendingPathComponent(trimmed)
        }

        return (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(trimmed)
    }

    private static func buildGlobPredicate(_ pattern: String) -> (String) -> Bool {
        // Convert glob pattern to regex
        var regex = "^"
        var i = pattern.startIndex

        while i < pattern.endIndex {
            let c = pattern[i]
            switch c {
            case "*":
                let next = pattern.index(after: i)
                if next < pattern.endIndex && pattern[next] == "*" {
                    // ** matches any path
                    regex += ".*"
                    let afterNext = pattern.index(after: next)
                    if afterNext < pattern.endIndex && pattern[afterNext] == "/" {
                        i = pattern.index(after: afterNext)
                        continue
                    }
                    i = afterNext
                    continue
                } else {
                    // * matches anything except /
                    regex += "[^/]*"
                }
            case "?":
                regex += "[^/]"
            case ".":
                regex += "\\."
            case "{":
                regex += "("
            case "}":
                regex += ")"
            case ",":
                regex += "|"
            default:
                regex += String(c)
            }
            i = pattern.index(after: i)
        }

        regex += "$"

        guard let compiledRegex = try? NSRegularExpression(pattern: regex, options: []) else {
            return { _ in false }
        }

        return { path in
            let range = NSRange(path.startIndex..., in: path)
            return compiledRegex.firstMatch(in: path, range: range) != nil
        }
    }
}
