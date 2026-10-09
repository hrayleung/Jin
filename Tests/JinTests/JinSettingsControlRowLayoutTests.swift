import AppKit
import SwiftUI
import XCTest
@testable import Jin

@MainActor
final class JinSettingsControlRowLayoutTests: XCTestCase {
    func testMultipleControlsStayInOneVerticalColumnAtSheetAndSettingsWidths() {
        _ = NSApplication.shared

        for width: CGFloat in [360, 480, 620] {
            let first = NSView()
            let second = NSView()
            let host = NSHostingView(rootView:
                JinSettingsControlRow("Environment", controlAlignment: .leading) {
                    LayoutProbe(view: first).frame(height: 24)
                    LayoutProbe(view: second).frame(height: 24)
                }
                .frame(width: width)
            )
            host.frame = NSRect(x: 0, y: 0, width: width, height: 120)
            host.layoutSubtreeIfNeeded()

            let firstFrame = first.convert(first.bounds, to: host)
            let secondFrame = second.convert(second.bounds, to: host)
            XCTAssertGreaterThan(firstFrame.width, 0)
            XCTAssertEqual(firstFrame.minX, secondFrame.minX, accuracy: 0.5)
            XCTAssertEqual(firstFrame.width, secondFrame.width, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(abs(firstFrame.minY - secondFrame.minY), 24)
            XCTAssertLessThanOrEqual(firstFrame.maxX, width + 0.5)
            XCTAssertLessThanOrEqual(secondFrame.maxX, width + 0.5)
        }
    }
}

private struct LayoutProbe: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
