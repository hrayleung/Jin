import Foundation

extension RTKRuntimeSupport {
    private static var fullOutputPrefix: String { "[full output:" }

    static func resolveRawOutputPath(in text: String) -> String? {
        let fileManager = FileManager.default
        let teeRootURL = (try? RTKConfigManager.teeDirectoryURL())?
            .standardizedFileURL
            .resolvingSymlinksInPath()

        for line in text.components(separatedBy: .newlines).reversed() {
            guard let trimmed = line.trimmedNonEmpty else { continue }
            guard trimmed.hasPrefix(fullOutputPrefix), trimmed.hasSuffix("]") else { continue }

            let startIndex = trimmed.index(trimmed.startIndex, offsetBy: fullOutputPrefix.count)
            guard let rawPath = String(trimmed[startIndex..<trimmed.index(before: trimmed.endIndex)]).trimmedNonEmpty else {
                continue
            }

            let resolvedPath: String
            if rawPath.hasPrefix("~/") {
                resolvedPath = FileManager.default.homeDirectoryForCurrentUser.path + String(rawPath.dropFirst(1))
            } else {
                resolvedPath = rawPath
            }

            let standardizedURL = URL(fileURLWithPath: resolvedPath)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard fileManager.fileExists(atPath: standardizedURL.path),
                  let teeRootURL,
                  isDescendant(standardizedURL, of: teeRootURL) else {
                continue
            }
            return standardizedURL.path
        }
        return nil
    }

    private static func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        let candidateComponents = candidate.pathComponents
        let rootComponents = root.pathComponents
        guard candidateComponents.count > rootComponents.count else { return false }
        return Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }
}
