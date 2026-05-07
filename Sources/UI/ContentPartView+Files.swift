import AppKit
import SwiftUI

extension ContentPartView {
    @ViewBuilder
    func fileContentView(_ file: RenderedFileContent) -> some View {
        let row = HStack {
            Image(systemName: "doc")
            Text(file.filename)
        }
        .padding(JinSpacing.small)
        .jinSurface(.neutral, cornerRadius: JinRadius.small)

        if let url = file.url {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                row
            }
            .buttonStyle(.plain)
            .help("Open \(file.filename)")
            .onDrag {
                NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
            }
            .contextMenu {
                fileContextMenu(file: file, url: url)
            }
        } else {
            row
                .contextMenu {
                    filenameOnlyContextMenu(file: file)
                }
        }
    }

    @ViewBuilder
    private func fileContextMenu(file: RenderedFileContent, url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label("Open", systemImage: "arrow.up.right.square")
        }

        Button {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }

        Divider()

        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(url.path, forType: .string)
        } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
        }

        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(file.filename, forType: .string)
        } label: {
            Label("Copy Filename", systemImage: "doc.on.doc")
        }

        extractedTextCopyButton(file)
    }

    @ViewBuilder
    private func filenameOnlyContextMenu(file: RenderedFileContent) -> some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(file.filename, forType: .string)
        } label: {
            Label("Copy Filename", systemImage: "doc.on.doc")
        }

        extractedTextCopyButton(file)
    }

    @ViewBuilder
    private func extractedTextCopyButton(_ file: RenderedFileContent) -> some View {
        if file.hasExtractedText {
            Divider()

            Button {
                Task {
                    await copyExtractedText(for: file)
                }
            } label: {
                Label("Copy Extracted Text", systemImage: "doc.on.doc")
            }
        }
    }

    @MainActor
    private func copyExtractedText(for file: RenderedFileContent) async {
        let extracted: String?
        if let immediate = file.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !immediate.isEmpty {
            extracted = immediate
        } else if let deferredSource = file.deferredSource {
            extracted = await payloadResolver.loadFileExtractedText(deferredSource)
        } else {
            extracted = nil
        }

        guard let extracted,
              !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(extracted, forType: .string)
    }
}
