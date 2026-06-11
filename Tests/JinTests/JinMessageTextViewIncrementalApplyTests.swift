import AppKit
import XCTest
@testable import Jin

/// `applyAttributedStringPreferringIncremental` — the streaming-flush apply.
/// A growing tail must append in place; ANY uncertainty must fall back to
/// the full scrubbed apply (the pre-existing behavior).
@MainActor
final class JinMessageTextViewIncrementalApplyTests: XCTestCase {
    private let font = NSFont.systemFont(ofSize: 14)
    private let boldFont = NSFont.boldSystemFont(ofSize: 14)

    private func attributed(_ string: String, bold: Bool = false) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: bold ? boldFont : font])
    }

    private func joined(_ parts: [NSAttributedString]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for part in parts { result.append(part) }
        return result
    }

    func testPureAppendTakesIncrementalPath() {
        let view = JinMessageTextView()
        view.setScrubbedAttributedString(attributed("第一段内容，"))

        let grown = attributed("第一段内容，第二段补充。")
        let mode = view.applyAttributedStringPreferringIncremental(grown)

        XCTAssertEqual(mode, .incremental)
        XCTAssertEqual(view.attributedString().string, grown.string)
    }

    func testRetroactiveAttributeChangeFallsBackToFullApply() {
        // A late `**` close re-bolds earlier characters: prefix text equal,
        // prefix attributes differ → full apply.
        let view = JinMessageTextView()
        view.setScrubbedAttributedString(joined([attributed("加粗"), attributed("继续")]))

        let restyled = joined([attributed("加粗", bold: true), attributed("继续更多")])
        let mode = view.applyAttributedStringPreferringIncremental(restyled)

        XCTAssertEqual(mode, .full)
        XCTAssertEqual(view.attributedString().string, restyled.string)
    }

    func testRetroactiveTextEditFallsBackToFullApply() {
        let view = JinMessageTextView()
        view.setScrubbedAttributedString(attributed("旧的前缀"))

        let rewritten = attributed("新的前缀加长版")
        let mode = view.applyAttributedStringPreferringIncremental(rewritten)

        XCTAssertEqual(mode, .full)
        XCTAssertEqual(view.attributedString().string, rewritten.string)
    }

    func testShrinkFallsBackToFullApply() {
        let view = JinMessageTextView()
        view.setScrubbedAttributedString(attributed("很长的一段内容"))

        let shorter = attributed("短")
        let mode = view.applyAttributedStringPreferringIncremental(shorter)

        XCTAssertEqual(mode, .full)
        XCTAssertEqual(view.attributedString().string, shorter.string)
    }

    func testEmptyStorageFallsBackToFullApply() {
        let view = JinMessageTextView()

        let mode = view.applyAttributedStringPreferringIncremental(attributed("首次内容"))

        XCTAssertEqual(mode, .full)
        XCTAssertEqual(view.attributedString().string, "首次内容")
    }

    func testBareObjectReplacementInTailIsScrubbedOnIncrementalPath() {
        let view = JinMessageTextView()
        view.setScrubbedAttributedString(attributed("前缀"))

        let grown = attributed("前缀x\u{FFFC}y")
        let mode = view.applyAttributedStringPreferringIncremental(grown)

        XCTAssertEqual(mode, .incremental)
        let result = view.attributedString().string
        XCTAssertFalse(result.utf16.contains(0xFFFC))
        XCTAssertEqual(result, "前缀x\u{FFFD}y")
    }

    func testSelectionSurvivesIncrementalAppend() {
        let view = JinMessageTextView()
        view.setScrubbedAttributedString(attributed("可选中的前缀内容"))
        view.setSelectedRange(NSRange(location: 1, length: 3))

        _ = view.applyAttributedStringPreferringIncremental(attributed("可选中的前缀内容，新增尾部"))

        XCTAssertEqual(view.selectedRange(), NSRange(location: 1, length: 3))
    }

    func testIncrementalAppendRelayoutsOnlyTheTail() {
        let view = JinMessageTextView()
        let prefix = "第一段落。\n\n第二段落。\n\n第三段落开头"
        view.setScrubbedAttributedString(attributed(prefix))
        guard let layoutManager = view.layoutManager, let storage = view.textStorage else {
            return XCTFail("TextKit 1 stack missing")
        }
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: storage.length))

        _ = view.applyAttributedStringPreferringIncremental(attributed(prefix + "继续生成的内容"))

        // Layout must stay valid at least through the paragraphs BEFORE the
        // edited one — TextKit only invalidates from the edited paragraph.
        let lastParagraphStart = (prefix as NSString).range(of: "第三段落").location
        XCTAssertGreaterThanOrEqual(
            layoutManager.firstUnlaidCharacterIndex(),
            lastParagraphStart,
            "incremental append must not invalidate layout of untouched paragraphs"
        )
    }
}
