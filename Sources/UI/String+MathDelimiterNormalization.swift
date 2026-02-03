import Foundation

extension String {
    func normalizingInlineMathDelimiters() -> String {
        self
            .replacingOccurrences(of: "＄", with: "$") // U+FF04 FULLWIDTH DOLLAR SIGN
            .replacingOccurrences(of: "﹩", with: "$") // U+FE69 SMALL DOLLAR SIGN
            .replacingOccurrences(of: "＼", with: "\\") // U+FF3C FULLWIDTH REVERSE SOLIDUS
            .replacingOccurrences(of: "﹨", with: "\\") // U+FE68 SMALL REVERSE SOLIDUS
            .replacingOccurrences(of: "∖", with: "\\") // U+2216 SET MINUS (sometimes used as backslash)
    }
}

