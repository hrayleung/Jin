import AppKit
import SwiftUI
import XCTest
@testable import Jin

@MainActor
final class OpenAIImage26PresentationTests: XCTestCase {
    func testAnimationPlaybackCanBeStopped() throws {
        _ = NSApplication.shared
        let image = try XCTUnwrap(AnimatedImagePreviewSupport.image(data: OpenAIImage26SupportTests.gif(), maxPixelSize: 200))
        let host = NSHostingView(rootView: AnyView(AnimatedImagePlaybackView(image: image, animates: true)))
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        host.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(imageView(in: host))
        XCTAssertTrue(view.animates)
        XCTAssertNotNil(view.image)
        host.rootView = AnyView(AnimatedImagePlaybackView(image: image, animates: false))
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(try XCTUnwrap(imageView(in: host)).animates)
    }

    func testImageSettingsSheetsRenderAtDeclaredSizes() throws {
        _ = NSApplication.shared
        let views: [(String, AnyView, NSSize)] = [
            ("animation", AnyView(OpenAIImageAnimationSheetView(controls: .init(outputFormat: .gif)) { _, _ in }), NSSize(width: 520, height: 340)),
            ("gif-size", AnyView(OpenAIImageCustomSizeSheetView(modelID: "gpt-image-2.6-flare", currentSize: .init(rawValue: "512x512"), outputFormat: .gif, onCancel: {}, onSave: { _ in })), NSSize(width: 520, height: 360)),
            ("model-settings", AnyView(ModelSettingsSheet(model: ModelCatalog.modelInfo(for: "gpt-image-2.6-sunburst", provider: .openai), providerType: .openai, onSave: { _ in })), NSSize(width: 600, height: 700))
        ]
        for (name, view, size) in views {
            let host = NSHostingView(rootView: view.environment(\.colorScheme, .light))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            host.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(host.fittingSize.width, size.width + 1)
            XCTAssertLessThanOrEqual(host.fittingSize.height, size.height + 1)
            if let directory = ProcessInfo.processInfo.environment["JIN_IMAGE26_SNAPSHOT_DIR"] {
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                let folder = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: folder.appendingPathComponent("\(name).png"))
            }
        }
    }

    private func imageView(in view: NSView) -> NSImageView? {
        if let image = view as? NSImageView { return image }
        return view.subviews.lazy.compactMap { self.imageView(in: $0) }.first
    }
}
