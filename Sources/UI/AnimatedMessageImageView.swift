import AppKit
import SwiftUI

struct AnimatedMessageImageView: View {
    let image: NSImage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AnimatedImagePlaybackView(image: image, animates: !reduceMotion)
    }
}

struct AnimatedImagePlaybackView: NSViewRepresentable {
    let image: NSImage
    let animates: Bool

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setAccessibilityLabel("Generated animation")
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if view.image !== image { view.image = image }
        view.animates = animates
    }

    static func dismantleNSView(_ view: NSImageView, coordinator: ()) {
        view.animates = false
        view.image = nil
    }
}
