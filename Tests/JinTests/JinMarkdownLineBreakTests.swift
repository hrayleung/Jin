import AppKit
import XCTest
@testable import Jin

final class JinMarkdownLineBreakTests: XCTestCase {

    func testKeepsShortEnglishParentheticalWithCJKText() {
        let lines = wrappedLines("操作系统内核 (Kernel) 的内存 Dump", width: 80)

        XCTAssertFalse(
            lines.contains { $0.hasPrefix("(Kernel)") },
            "English parenthetical should not be orphaned at line start: \(lines)"
        )
    }

    func testKeepsShortFullwidthEnglishParentheticalWithCJKText() {
        let lines = wrappedLines("操作系统内核（Kernel）的内存 Dump", width: 80)

        XCTAssertFalse(
            lines.contains { $0.hasPrefix("（Kernel）") },
            "Fullwidth English parenthetical should not be orphaned at line start: \(lines)"
        )
    }

    private func wrappedLines(_ text: String, width: CGFloat) -> [String] {
        let storage = NSTextStorage(attributedString: NSAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: 14)]
        ))
        let layout = JinMarkdownLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)

        var lines: [String] = []
        var glyphIndex = 0
        while glyphIndex < layout.numberOfGlyphs {
            var glyphRange = NSRange()
            layout.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &glyphRange)
            let characterRange = layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            lines.append((text as NSString).substring(with: characterRange))
            glyphIndex = glyphRange.upperBound
        }
        return lines
    }
}
