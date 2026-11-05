import Foundation

/// GPT Image SVG output is static vector XML. Reject active or external content
/// before it reaches a native preview or an exported file.
enum OpenAIImageSVGValidation {
    static func validate(_ data: Data) throws {
        guard let xml = String(data: data, encoding: .utf8),
              !xml.localizedCaseInsensitiveContains("<!DOCTYPE"),
              !xml.localizedCaseInsensitiveContains("<!ENTITY") else {
            throw invalidSVG
        }
        let validator = Validator()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = true
        parser.delegate = validator
        guard parser.parse(), validator.valid, validator.hasRoot else { throw invalidSVG }
    }

    private static var invalidSVG: LLMError {
        .decodingError(message: "The image service returned an invalid SVG or content outside the supported static vector format.")
    }

    private final class Validator: NSObject, XMLParserDelegate {
        var valid = true
        var hasRoot = false
        private var styleText: String?
        private static let urlPattern = try? NSRegularExpression(pattern: #"url\s*\(([^)]*)\)"#)
        private let elements: Set<String> = [
            "svg", "g", "defs", "symbol", "use", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon",
            "text", "tspan", "textPath", "title", "desc", "metadata", "linearGradient", "radialGradient", "stop",
            "clipPath", "mask", "pattern", "filter", "feBlend", "feColorMatrix", "feComponentTransfer",
            "feComposite", "feConvolveMatrix", "feDiffuseLighting", "feDisplacementMap", "feDistantLight",
            "feDropShadow", "feFlood", "feFuncA", "feFuncB", "feFuncG", "feFuncR", "feGaussianBlur", "feMerge",
            "feMergeNode", "feMorphology", "feOffset", "fePointLight", "feSpecularLighting", "feSpotLight",
            "feTile", "feTurbulence", "style"
        ]

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            if !hasRoot {
                hasRoot = name == "svg"
                if !hasRoot { reject(parser); return }
            }
            guard elements.contains(name), namespaceURI == nil || namespaceURI == "http://www.w3.org/2000/svg" else {
                reject(parser); return
            }
            if name == "style" { styleText = "" }
            for (key, value) in attributes {
                let key = key.lowercased()
                if key.hasPrefix("on") || key == "xml:base" || key == "src" { reject(parser); return }
                if key == "href" || key.hasSuffix(":href") {
                    guard value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#") else { reject(parser); return }
                }
                if !safeCSS(value) { reject(parser); return }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if styleText != nil { styleText?.append(string) }
        }

        func parser(_ parser: XMLParser, foundCDATA data: Data) {
            if styleText != nil {
                guard let text = String(data: data, encoding: .utf8) else { reject(parser); return }
                styleText?.append(text)
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "style", let text = styleText {
                if !safeCSS(text) { reject(parser) }
                styleText = nil
            }
        }

        func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) {
            reject(parser)
        }

        private func safeCSS(_ value: String) -> Bool {
            let lower = value.lowercased()
            guard !lower.contains("@"), !lower.contains("\\") else { return false }
            guard let regex = Self.urlPattern else { return false }
            let text = lower as NSString
            return regex.matches(in: lower, range: NSRange(location: 0, length: text.length)).allSatisfy {
                text.substring(with: $0.range(at: 1)).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'"))).hasPrefix("#")
            }
        }

        private func reject(_ parser: XMLParser) { valid = false; parser.abortParsing() }
    }
}
