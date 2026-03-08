import Foundation

enum ArtifactContentType: String, Codable, CaseIterable, Hashable, Sendable {
    case html = "text/html"
    case react = "application/vnd.jin.react"
    case echarts = "application/vnd.jin.echarts.option+json"

    var displayName: String {
        switch self {
        case .html:
            return "HTML"
        case .react:
            return "React"
        case .echarts:
            return "ECharts"
        }
    }

    var fileExtension: String {
        switch self {
        case .html:
            return "html"
        case .react:
            return "tsx"
        case .echarts:
            return "json"
        }
    }

    var codeFenceLanguage: String {
        switch self {
        case .html:
            return "html"
        case .react:
            return "tsx"
        case .echarts:
            return "json"
        }
    }
}

struct ParsedArtifact: Identifiable, Codable, Hashable, Sendable {
    let artifactID: String
    let title: String
    let contentType: ArtifactContentType
    let content: String

    var id: String { artifactID }
}

struct ArtifactParseResult: Sendable {
    let visibleTextSegments: [String]
    let artifacts: [ParsedArtifact]
    let hasIncompleteTrailingArtifact: Bool

    var visibleText: String {
        visibleTextSegments.joined()
    }
}

enum ArtifactMarkupParser {
    static let tagName = "jinArtifact"

    private static let openingTagMarker = "<\(tagName)"
    private static let closingTag = "</\(tagName)>"
    private static let attributeRegex = try! NSRegularExpression(
        pattern: #"([A-Za-z_][A-Za-z0-9_:\-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')"#
    )

    static func parse(_ text: String, hidesTrailingIncompleteArtifact: Bool = false) -> ArtifactParseResult {
        let nsText = text as NSString
        var visibleSegments: [String] = []
        var artifacts: [ParsedArtifact] = []
        var cursor = 0
        var hasIncompleteTrailingArtifact = false

        while cursor < nsText.length {
            let remainingRange = NSRange(location: cursor, length: nsText.length - cursor)
            let openRange = nsText.range(
                of: openingTagMarker,
                options: [.caseInsensitive],
                range: remainingRange
            )

            guard openRange.location != NSNotFound else {
                let trailing = nsText.substring(with: remainingRange)
                if !trailing.isEmpty {
                    visibleSegments.append(trailing)
                }
                break
            }

            let leadingRange = NSRange(location: cursor, length: openRange.location - cursor)
            if leadingRange.length > 0 {
                visibleSegments.append(nsText.substring(with: leadingRange))
            }

            let openTagSearchRange = NSRange(
                location: NSMaxRange(openRange),
                length: nsText.length - NSMaxRange(openRange)
            )
            let tagEndRange = nsText.range(of: ">", options: [], range: openTagSearchRange)

            guard tagEndRange.location != NSNotFound else {
                hasIncompleteTrailingArtifact = true
                if !hidesTrailingIncompleteArtifact {
                    visibleSegments.append(nsText.substring(with: NSRange(location: openRange.location, length: nsText.length - openRange.location)))
                }
                break
            }

            let contentStart = NSMaxRange(tagEndRange)
            let closeSearchRange = NSRange(location: contentStart, length: nsText.length - contentStart)
            let closeRange = nsText.range(of: closingTag, options: [.caseInsensitive], range: closeSearchRange)

            guard closeRange.location != NSNotFound else {
                hasIncompleteTrailingArtifact = true
                if !hidesTrailingIncompleteArtifact {
                    visibleSegments.append(nsText.substring(with: NSRange(location: openRange.location, length: nsText.length - openRange.location)))
                }
                break
            }

            let openingTagRange = NSRange(location: openRange.location, length: NSMaxRange(tagEndRange) - openRange.location)
            let rawBlockRange = NSRange(location: openRange.location, length: NSMaxRange(closeRange) - openRange.location)
            let contentRange = NSRange(location: contentStart, length: closeRange.location - contentStart)
            let openingTag = nsText.substring(with: openingTagRange)
            let content = nsText.substring(with: contentRange)

            if let artifact = parsedArtifact(fromOpeningTag: openingTag, content: content) {
                artifacts.append(artifact)
            } else {
                visibleSegments.append(nsText.substring(with: rawBlockRange))
            }

            cursor = NSMaxRange(closeRange)
        }

        return ArtifactParseResult(
            visibleTextSegments: visibleSegments,
            artifacts: artifacts,
            hasIncompleteTrailingArtifact: hasIncompleteTrailingArtifact
        )
    }

    static func visibleText(from text: String, hidesTrailingIncompleteArtifact: Bool = false) -> String {
        parse(text, hidesTrailingIncompleteArtifact: hidesTrailingIncompleteArtifact).visibleText
    }

    static func containsCompleteArtifact(in text: String) -> Bool {
        !parse(text).artifacts.isEmpty
    }

    static func appendingInstructions(to systemPrompt: String?, enabled: Bool) -> String? {
        guard enabled else {
            let trimmed = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }

        let base = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions = """
When you need to return a renderable artifact for Jin, wrap it in a <jinArtifact> block.

Artifact protocol:
- Use exactly: <jinArtifact artifact_id="stable-id" title="Short Title" contentType="SUPPORTED_TYPE"> ... </jinArtifact>
- Supported contentType values: text/html, application/vnd.jin.react, application/vnd.jin.echarts.option+json
- Reuse the same artifact_id when revising the same artifact in later replies
- Keep normal conversational text outside the artifact tag
- React artifacts must define a top-level component named ArtifactApp
- ECharts artifacts must contain JSON only
- For SVG, Mermaid, or Markdown content, use regular code blocks instead of artifacts
"""

        guard let base, !base.isEmpty else {
            return instructions
        }

        return "\(base)\n\n\(instructions)"
    }

    private static func parsedArtifact(fromOpeningTag openingTag: String, content: String) -> ParsedArtifact? {
        let attributes = parseAttributes(in: openingTag)

        guard let artifactID = attributes["artifact_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !artifactID.isEmpty,
              let rawContentType = attributes["contentType"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let contentType = ArtifactContentType(rawValue: rawContentType) else {
            return nil
        }

        let title = attributes["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = (title?.isEmpty == false) ? title! : artifactID
        let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedArtifact(
            artifactID: artifactID,
            title: resolvedTitle,
            contentType: contentType,
            content: normalizedContent
        )
    }

    private static func parseAttributes(in openingTag: String) -> [String: String] {
        let nsTag = openingTag as NSString
        let fullRange = NSRange(location: 0, length: nsTag.length)
        var attributes: [String: String] = [:]

        for match in attributeRegex.matches(in: openingTag, range: fullRange) {
            guard match.numberOfRanges >= 4 else { continue }

            let keyRange = match.range(at: 1)
            guard keyRange.location != NSNotFound else { continue }
            let key = nsTag.substring(with: keyRange)

            let doubleQuotedRange = match.range(at: 2)
            let singleQuotedRange = match.range(at: 3)
            let valueRange = doubleQuotedRange.location != NSNotFound ? doubleQuotedRange : singleQuotedRange

            guard valueRange.location != NSNotFound else { continue }
            attributes[key] = nsTag.substring(with: valueRange)
        }

        return attributes
    }
}
