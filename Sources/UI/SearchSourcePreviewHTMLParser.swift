import Foundation

enum SearchSourcePreviewHTMLParser {
    private static let maxPreviewLength = 420
    private static let preferredMetaKeys = [
        "og:description",
        "twitter:description",
        "description",
        "dc.description",
        "sailthru.description"
    ]
    private static let metaTagRegex = try! NSRegularExpression(pattern: "(?is)<meta\\b[^>]*>")
    private static let attributeRegex = try! NSRegularExpression(
        pattern: "(?is)([a-zA-Z_:.-]+)\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s\"'=<>`]+))"
    )
    private static let jsonLDScriptRegex = try! NSRegularExpression(
        pattern: "(?is)<script\\b[^>]*type\\s*=\\s*(['\"])application/ld\\+json\\1[^>]*>(.*?)</script>"
    )
    private static let scriptRegex = try! NSRegularExpression(pattern: "(?is)<script\\b[^>]*>.*?</script>")
    private static let styleRegex = try! NSRegularExpression(pattern: "(?is)<style\\b[^>]*>.*?</style>")
    private static let paragraphRegex = try! NSRegularExpression(pattern: "(?is)<p\\b[^>]*>(.*?)</p>")
    private static let titleRegex = try! NSRegularExpression(pattern: "(?is)<title\\b[^>]*>(.*?)</title>")
    private static let numericEntityRegex = try! NSRegularExpression(pattern: "&#(x?[0-9A-Fa-f]+);")

    private struct Candidate {
        let text: String
        let source: CandidateSource
    }

    private enum CandidateSource {
        case meta(index: Int)
        case jsonLD
        case paragraph
        case title

        var baseScore: Int {
            switch self {
            case .meta(let index):
                return 620 - (index * 24)
            case .jsonLD:
                return 540
            case .paragraph:
                return 500
            case .title:
                return 180
            }
        }
    }

    static func extractPreview(from html: String) -> String? {
        let metaValues = metaContentValues(in: html)
        let sanitizedHTML = sanitizeHTML(html)
        var candidates: [Candidate] = []

        for (index, key) in preferredMetaKeys.enumerated() {
            if let value = metaValues[key] {
                candidates.append(Candidate(text: value, source: .meta(index: index)))
            }
        }

        if let jsonLD = jsonLDDescription(in: html) {
            candidates.append(Candidate(text: jsonLD, source: .jsonLD))
        }

        if let firstParagraph = firstTagText(using: paragraphRegex, in: sanitizedHTML) {
            candidates.append(Candidate(text: firstParagraph, source: .paragraph))
        }

        if let title = firstTagText(using: titleRegex, in: sanitizedHTML) {
            candidates.append(Candidate(text: title, source: .title))
        }

        return candidates.max(by: { candidateScore($0) < candidateScore($1) })?.text
    }

    private static func sanitizeHTML(_ html: String) -> String {
        replaceMatches(of: styleRegex, in: replaceMatches(of: scriptRegex, in: html))
    }

    private static func metaContentValues(in html: String) -> [String: String] {
        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)
        let tagMatches = metaTagRegex.matches(in: html, range: fullRange)

        var out: [String: String] = [:]
        for tagMatch in tagMatches {
            let tag = nsHTML.substring(with: tagMatch.range)
            let attributes = parseAttributes(in: tag, using: attributeRegex)
            let key = (attributes["property"] ?? attributes["name"] ?? attributes["itemprop"])?.lowercased()
            guard let key, !key.isEmpty, out[key] == nil else { continue }
            guard let normalizedContent = normalizeCandidate(attributes["content"]) else { continue }
            out[key] = normalizedContent
        }

        return out
    }

    private static func jsonLDDescription(in html: String) -> String? {
        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)
        let matches = jsonLDScriptRegex.matches(in: html, range: fullRange)

        for match in matches where match.numberOfRanges > 2 {
            let rawJSON = nsHTML.substring(with: match.range(at: 2))
            let decodedJSON = decodeHTMLEntities(rawJSON).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !decodedJSON.isEmpty, let data = decodedJSON.data(using: .utf8) else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: data) else { continue }

            if let description = firstStringValue(forKeys: ["description", "headline"], in: object),
               let normalized = normalizeCandidate(description) {
                return normalized
            }
        }

        return nil
    }

    private static func firstStringValue(forKeys keys: [String], in object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            for key in keys {
                if let value = dictionary[key] as? String,
                   let normalized = normalizeCandidate(value) {
                    return normalized
                }
            }

            for value in dictionary.values {
                if let nested = firstStringValue(forKeys: keys, in: value) {
                    return nested
                }
            }
        } else if let array = object as? [Any] {
            for item in array {
                if let nested = firstStringValue(forKeys: keys, in: item) {
                    return nested
                }
            }
        }

        return nil
    }

    private static func parseAttributes(in tag: String, using regex: NSRegularExpression) -> [String: String] {
        let nsTag = tag as NSString
        let matches = regex.matches(in: tag, range: NSRange(location: 0, length: nsTag.length))

        var attributes: [String: String] = [:]
        for match in matches where match.numberOfRanges >= 6 {
            let name = nsTag.substring(with: match.range(at: 1)).lowercased()
            let rawValueRange = [3, 4, 5]
                .map { match.range(at: $0) }
                .first(where: { $0.location != NSNotFound && $0.length > 0 })

            guard let rawValueRange else { continue }
            let rawValue = nsTag.substring(with: rawValueRange)
            attributes[name] = decodeHTMLEntities(rawValue)
        }

        return attributes
    }

    private static func firstTagText(using regex: NSRegularExpression, in html: String) -> String? {
        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)
        guard let match = regex.firstMatch(in: html, range: fullRange), match.numberOfRanges > 1 else {
            return nil
        }

        let raw = nsHTML.substring(with: match.range(at: 1))
        return normalizeCandidate(raw)
    }

    private static func normalizeCandidate(_ raw: String?) -> String? {
        guard let raw else { return nil }

        let withoutTags = raw.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let decoded = decodeHTMLEntities(withoutTags)
        let collapsed = decoded
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else { return nil }
        if collapsed.count <= maxPreviewLength {
            return collapsed
        }
        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: maxPreviewLength)
        return String(collapsed[..<endIndex]) + "…"
    }

    private static func candidateScore(_ candidate: Candidate) -> Int {
        let wordCount = candidate.text.split(whereSeparator: \.isWhitespace).count
        let lengthScore = min(candidate.text.count, maxPreviewLength)
        let densityScore = min(wordCount * 8, 120)
        return candidate.source.baseScore + lengthScore + densityScore
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        var out = value
        let namedReplacements: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&#34;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&ldquo;", "\""),
            ("&rdquo;", "\""),
            ("&lsquo;", "'"),
            ("&rsquo;", "'"),
            ("&ndash;", "-"),
            ("&mdash;", "-"),
            ("&hellip;", "…")
        ]

        for (from, to) in namedReplacements {
            out = out.replacingOccurrences(of: from, with: to)
        }

        let nsOut = out as NSString
        let matches = numericEntityRegex.matches(in: out, range: NSRange(location: 0, length: nsOut.length))

        for match in matches.reversed() where match.numberOfRanges > 1 {
            let entityValue = nsOut.substring(with: match.range(at: 1))
            let scalarValue: UInt32?
            if entityValue.hasPrefix("x") || entityValue.hasPrefix("X") {
                scalarValue = UInt32(entityValue.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(entityValue, radix: 10)
            }

            guard let scalarValue,
                  let scalar = UnicodeScalar(scalarValue) else {
                continue
            }

            out = (out as NSString).replacingCharacters(in: match.range, with: String(Character(scalar)))
        }

        return out
    }

    private static func replaceMatches(
        of regex: NSRegularExpression,
        in input: String
    ) -> String {
        regex.stringByReplacingMatches(
            in: input,
            range: NSRange(location: 0, length: (input as NSString).length),
            withTemplate: " "
        )
    }
}
