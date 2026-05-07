import Foundation

extension MarkdownRenderPreparation {
    static func anomalyScore(in markdown: String) -> Int {
        var score = 0

        _ = transformOutsideProtectedBlocks(in: markdown) { line in
            let protectedLine = preserveInlineCode(in: line) { $0 }

            if matches(#"^( {0,3}#{1,6})(?=\S)"#, in: protectedLine) {
                score += 3
            }
            if matches(#"(?<=\S)\s+(#{1,6})(?=[#\dA-Za-z\p{Han}])"#, in: protectedLine) {
                score += 2
            }
            if matches(#"(?<=\S)(?<![*+-])(?:-\s+(?=(?:\*\*)?[\p{L}\p{N}])|\*\s+(?=[\p{L}\p{N}])|\+\s+(?=[\p{L}\p{N}]))"#, in: protectedLine) {
                score += 2
            }
            if matches(#"(?<=[\.:：;；\)])\s*(\d{1,2}[.)])\s+(?=[\p{L}\p{N}])"#, in: protectedLine) {
                score += 1
            }
            if hasEscapedLeadingEmphasis(in: protectedLine) {
                score += 1
            }
            if matches(#"(?<!^)(?<!\n)(?<!-)(---+)(?=(?:#{1,6}\S| {0,3}[-*+]\s|$))"#, in: protectedLine) {
                score += 2
            }
            if lineHasInlineTableBreakage(protectedLine) {
                score += 2
            }
            if headingBodySplitIndex(in: protectedLine) != nil {
                score += 1
            }

            return protectedLine
        }

        return score
    }
}
