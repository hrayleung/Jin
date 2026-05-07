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

    /// Resumable scan state for streaming inputs. Holding this across calls makes
    /// per-call work O(delta-since-last-call) instead of O(total-text). Reset to
    /// `.initial` whenever the input is replaced (not just appended).
    struct ScanState: Sendable {
        /// NSString position from which the next `parse` call should resume
        /// scanning for `<jinArtifact` markers. Always advanced past
        /// fully-closed artifacts and through verified-marker-free tail text
        /// (with a small retention window so a partial marker straddling
        /// flush boundaries is caught).
        fileprivate var cursor: Int = 0
        fileprivate var lastTextLength: Int = 0
        /// NSString position where the visible chunk after the last closed
        /// artifact begins. The "active chunk" of visible text is always
        /// derived as `nsText.substring([committedActiveChunkBase, end))`.
        fileprivate var committedActiveChunkBase: Int = 0
        /// Visible text segments fully bounded by closed artifacts (or by
        /// the start of the input). Stable across subsequent calls.
        fileprivate var committedSegments: [String] = []
        fileprivate var committedArtifacts: [ParsedArtifact] = []

        public static let initial = ScanState()
    }

    static func parse(_ text: String, hidesTrailingIncompleteArtifact: Bool = false) -> ArtifactParseResult {
        var state = ScanState.initial
        return parse(text, hidesTrailingIncompleteArtifact: hidesTrailingIncompleteArtifact, state: &state)
    }

    static func parse(
        _ text: String,
        hidesTrailingIncompleteArtifact: Bool = false,
        state: inout ScanState
    ) -> ArtifactParseResult {
        let nsText = text as NSString

        if nsText.length < state.lastTextLength || nsText.length < state.cursor {
            state = .initial
        }

        var cursor = state.cursor
        var hasIncompleteTrailingArtifact = false

        while cursor < nsText.length {
            let remainingRange = NSRange(location: cursor, length: nsText.length - cursor)
            let openRange = nsText.range(
                of: openingTagMarker,
                options: [.caseInsensitive],
                range: remainingRange
            )

            guard openRange.location != NSNotFound else {
                // No marker in [cursor, end). We can advance the scan cursor
                // past everything except a retention window large enough to
                // catch a partial opening marker that straddles flush
                // boundaries.
                let retention = openingTagMarker.count
                let safeCommitLocation = nsText.length - retention
                if safeCommitLocation > cursor {
                    cursor = safeCommitLocation
                }
                break
            }

            let openTagSearchRange = NSRange(
                location: NSMaxRange(openRange),
                length: nsText.length - NSMaxRange(openRange)
            )
            let tagEndRange = nsText.range(of: ">", options: [], range: openTagSearchRange)

            guard tagEndRange.location != NSNotFound else {
                hasIncompleteTrailingArtifact = true
                cursor = openRange.location
                break
            }

            let contentStart = NSMaxRange(tagEndRange)
            let closeSearchRange = NSRange(location: contentStart, length: nsText.length - contentStart)
            let closeRange = nsText.range(of: closingTag, options: [.caseInsensitive], range: closeSearchRange)

            guard closeRange.location != NSNotFound else {
                hasIncompleteTrailingArtifact = true
                cursor = openRange.location
                break
            }

            // Complete artifact: commit the active chunk before this
            // artifact, then commit the artifact itself.
            if openRange.location > state.committedActiveChunkBase {
                let chunk = nsText.substring(with: NSRange(
                    location: state.committedActiveChunkBase,
                    length: openRange.location - state.committedActiveChunkBase
                ))
                state.committedSegments.append(chunk)
            }

            let openingTagRange = NSRange(location: openRange.location, length: NSMaxRange(tagEndRange) - openRange.location)
            let rawBlockRange = NSRange(location: openRange.location, length: NSMaxRange(closeRange) - openRange.location)
            let contentRange = NSRange(location: contentStart, length: closeRange.location - contentStart)
            let openingTag = nsText.substring(with: openingTagRange)
            let content = nsText.substring(with: contentRange)

            if let artifact = parsedArtifact(fromOpeningTag: openingTag, content: content) {
                state.committedArtifacts.append(artifact)
            } else {
                // Unsupported contentType — fall back to surfacing the raw
                // block as its own visible segment, matching the
                // non-resumable parser's behaviour.
                state.committedSegments.append(nsText.substring(with: rawBlockRange))
            }

            cursor = NSMaxRange(closeRange)
            state.committedActiveChunkBase = cursor
        }

        state.cursor = cursor
        state.lastTextLength = nsText.length

        var resultSegments = state.committedSegments

        let activeChunkEnd: Int
        if hasIncompleteTrailingArtifact {
            activeChunkEnd = state.cursor
        } else {
            activeChunkEnd = nsText.length
        }

        if activeChunkEnd > state.committedActiveChunkBase {
            let active = nsText.substring(with: NSRange(
                location: state.committedActiveChunkBase,
                length: activeChunkEnd - state.committedActiveChunkBase
            ))
            if !active.isEmpty {
                resultSegments.append(active)
            }
        }

        if hasIncompleteTrailingArtifact, !hidesTrailingIncompleteArtifact, state.cursor < nsText.length {
            let raw = nsText.substring(with: NSRange(
                location: state.cursor,
                length: nsText.length - state.cursor
            ))
            if !raw.isEmpty {
                resultSegments.append(raw)
            }
        }

        return ArtifactParseResult(
            visibleTextSegments: resultSegments,
            artifacts: state.committedArtifacts,
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
            return systemPrompt?.trimmedNonEmpty
        }

        let base = systemPrompt?.trimmedNonEmpty
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

        guard let base else {
            return instructions
        }

        return "\(base)\n\n\(instructions)"
    }

    private static func parsedArtifact(fromOpeningTag openingTag: String, content: String) -> ParsedArtifact? {
        let attributes = parseAttributes(in: openingTag)

        guard let artifactID = attributes["artifact_id"]?.trimmedNonEmpty,
              let rawContentType = attributes["contentType"]?.trimmed,
              let contentType = ArtifactContentType(rawValue: rawContentType) else {
            return nil
        }

        let resolvedTitle = attributes["title"]?.trimmedNonEmpty ?? artifactID
        let normalizedContent = content.trimmed

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
