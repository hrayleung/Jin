import AppKit
import AVFoundation
import AVKit
import SwiftUI

extension ContentPartView {
    @ViewBuilder
    func renderedVideo(_ video: VideoContent) -> some View {
        if let fileURL = video.url, fileURL.isFileURL {
            VideoPlayerView(url: fileURL)
                .frame(maxWidth: 560, minHeight: 220, maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
        } else if let url = video.url {
            VideoPlayerView(url: url)
                .frame(maxWidth: 560, minHeight: 220, maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
        } else if let data = video.data {
            Label("Video data (\(data.count) bytes)", systemImage: "video")
                .padding(JinSpacing.small)
                .jinSurface(.neutral, cornerRadius: JinRadius.small)
        } else {
            Label("Video", systemImage: "video")
                .padding(JinSpacing.small)
                .jinSurface(.neutral, cornerRadius: JinRadius.small)
        }
    }
}

/// Custom AVPlayerView that provides a native context menu with Reveal in Finder,
/// since SwiftUI `.contextMenu` does not receive right-click events from NSViewRepresentable.
private final class JinAVPlayerView: AVPlayerView {
    var mediaURL: URL?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let url = mediaURL else { return nil }

        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open", action: #selector(openMedia), keyEquivalent: "")
        openItem.target = self
        openItem.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: nil)
        menu.addItem(openItem)

        let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(revealInFinder), keyEquivalent: "")
        revealItem.target = self
        revealItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        menu.addItem(revealItem)

        menu.addItem(.separator())

        if url.isFileURL {
            let copyItem = NSMenuItem(title: "Copy Path", action: #selector(copyPathOrURL), keyEquivalent: "")
            copyItem.target = self
            copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
            menu.addItem(copyItem)
        } else {
            let copyItem = NSMenuItem(title: "Copy URL", action: #selector(copyPathOrURL), keyEquivalent: "")
            copyItem.target = self
            copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
            menu.addItem(copyItem)
        }

        return menu
    }

    @objc private func openMedia() {
        guard let url = mediaURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func revealInFinder() {
        guard let url = mediaURL else { return }
        if url.isFileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            Task {
                if let localURL = await MessageMediaAssetPersistenceSupport.persistRemoteVideoToDisk(from: url) {
                    await MainActor.run {
                        NSWorkspace.shared.activateFileViewerSelecting([localURL])
                    }
                }
            }
        }
    }

    @objc private func copyPathOrURL() {
        guard let url = mediaURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.isFileURL ? url.path : url.absoluteString, forType: .string)
    }
}

/// Wraps JinAVPlayerView to provide video playback with a native context menu.
private struct VideoPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> JinAVPlayerView {
        let view = JinAVPlayerView()
        view.player = AVPlayer(url: url)
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.mediaURL = url
        return view
    }

    func updateNSView(_ nsView: JinAVPlayerView, context: Context) {
        if (nsView.player?.currentItem?.asset as? AVURLAsset)?.url != url {
            nsView.player = AVPlayer(url: url)
            nsView.mediaURL = url
        }
    }
}
