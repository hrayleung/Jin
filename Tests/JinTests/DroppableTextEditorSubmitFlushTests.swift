import XCTest
import AppKit
import SwiftUI
@testable import Jin

/// Enter must send inside the same event turn the key arrived in.
///
/// Typing deliberately defers the NSTextView→binding write by one runloop turn
/// (that deferral is the composer typing-latency fix). Submit used to inherit
/// it wholesale — the whole send was wrapped in `DispatchQueue.main.async` — so
/// every Enter spent a full runloop turn in which nothing happened at all, in
/// both the composer and the in-bubble message editor. The send now drains that
/// pending write itself, which is what makes the synchronous path safe.
@MainActor
final class DroppableTextEditorSubmitFlushTests: XCTestCase {

    private final class TextBox {
        var value: String = ""
    }

    private struct Harness {
        let textView: DroppableNSTextView
        let box: TextBox
        /// Binding value observed at the moment `onSubmit` fired.
        let submittedText: () -> String?
        let submitCount: () -> Int
    }

    /// Mirrors the wiring `DroppableTextEditor.makeNSView` performs.
    private func makeHarness(useCommandEnterToSubmit: Bool = false) -> Harness {
        let box = TextBox()
        let binding = Binding<String>(get: { box.value }, set: { box.value = $0 })
        var submitted: String?
        var submitCount = 0

        let coordinator = DroppableTextEditor.Coordinator(
            text: binding,
            isDropTargeted: .constant(false),
            isFocused: .constant(false),
            onDropFileURLs: { _ in false },
            onDropImages: { _ in false },
            onSubmit: {
                submitCount += 1
                submitted = box.value
            },
            onCancel: { false }
        )

        let textView = DroppableNSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        textView.delegate = coordinator
        textView.useCommandEnterToSubmit = useCommandEnterToSubmit
        textView.onFlushPendingText = { [weak textView] in
            guard let textView else { return }
            coordinator.flushPendingBinding(for: textView)
        }
        textView.onSubmit = { coordinator.submit() }
        textView.onCancel = { coordinator.cancel() }

        // Keep the coordinator alive for the lifetime of the harness: the text
        // view's delegate reference is weak.
        objc_setAssociatedObject(textView, "coordinator", coordinator, .OBJC_ASSOCIATION_RETAIN)

        return Harness(
            textView: textView,
            box: box,
            submittedText: { submitted },
            submitCount: { submitCount }
        )
    }

    /// Simulates typing: the text view's string is the source of truth and the
    /// binding write is only *scheduled*, exactly as during real keystrokes.
    private func type(_ text: String, into harness: Harness) {
        harness.textView.string = text
        harness.textView.didChangeText()
    }

    private func returnKeyEvent(modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )!
    }

    func testEnterSubmitsSynchronouslyWithTheLastTypedCharacter() {
        let harness = makeHarness()
        type("你好", into: harness)
        // The deferred flush has not run: the binding is still stale.
        XCTAssertEqual(harness.box.value, "")

        harness.textView.keyDown(with: returnKeyEvent())

        // Submitted without waiting a runloop turn...
        XCTAssertEqual(harness.submitCount(), 1)
        // ...and it saw the full draft, not the pre-keystroke value.
        XCTAssertEqual(harness.submittedText(), "你好")
    }

    /// The queued flush must not resurrect the draft after the send cleared it.
    func testPendingFlushDoesNotRestoreTextAfterSubmitClearsIt() {
        let harness = makeHarness()
        type("hello", into: harness)
        harness.textView.keyDown(with: returnKeyEvent())
        XCTAssertEqual(harness.submittedText(), "hello")

        // Send path clears the draft, and SwiftUI pushes that back down.
        harness.box.value = ""
        harness.textView.syncExternalTextIfNeeded("")

        let drained = expectation(description: "queued binding flush ran")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)

        XCTAssertEqual(harness.box.value, "")
        XCTAssertEqual(harness.textView.string, "")
    }

    func testShiftEnterInsertsNewlineInsteadOfSubmitting() {
        let harness = makeHarness()
        type("hello", into: harness)

        harness.textView.keyDown(with: returnKeyEvent(modifiers: .shift))

        XCTAssertEqual(harness.submitCount(), 0)
    }

    func testCommandEnterModeOnlySubmitsWithCommand() {
        let harness = makeHarness(useCommandEnterToSubmit: true)
        type("hello", into: harness)

        harness.textView.keyDown(with: returnKeyEvent())
        XCTAssertEqual(harness.submitCount(), 0)

        harness.textView.keyDown(with: returnKeyEvent(modifiers: .command))
        XCTAssertEqual(harness.submitCount(), 1)
        XCTAssertEqual(harness.submittedText(), "hello")
    }

    /// IME safety: while a candidate is still being composed, Return belongs to
    /// the input method and must not reach the send path.
    func testReturnDuringIMECompositionDoesNotSubmit() {
        let harness = makeHarness()
        harness.textView.setMarkedText(
            "nihao",
            selectedRange: NSRange(location: 5, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertTrue(harness.textView.hasMarkedText())

        harness.textView.keyDown(with: returnKeyEvent())

        XCTAssertEqual(harness.submitCount(), 0)
    }
}
