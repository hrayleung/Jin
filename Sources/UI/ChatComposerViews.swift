import SwiftUI
import AppKit

// MARK: - Constants

enum AttachmentConstants {
    static let maxDraftAttachments = 8
    static let maxAttachmentBytes = 25 * 1024 * 1024
    static let maxPDFExtractedCharacters = 120_000
    static let maxMistralOCRImagesToAttach = 8
    static let maxMistralOCRTotalImageBytes = 12 * 1024 * 1024
}

// MARK: - Error

struct AttachmentImportError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? { message }
}

// MARK: - Draft Attachment

struct DraftAttachment: Identifiable, Hashable, Sendable {
    let id: UUID
    let filename: String
    let mimeType: String
    let fileURL: URL
    let extractedText: String?

    var isImage: Bool { mimeType.hasPrefix("image/") }
    var isPDF: Bool { mimeType == "application/pdf" }
}

// MARK: - Draft Attachment Chip

struct DraftAttachmentChip: View {
    let attachment: DraftAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            thumbnailView
                .frame(width: 26, height: 26)

            Text(attachment.filename)
                .font(.caption)
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, JinSpacing.medium - 2)
        .padding(.vertical, JinSpacing.xSmall + 2)
        .jinSurface(.neutral, cornerRadius: JinRadius.medium)
        .onDrag {
            NSItemProvider(contentsOf: attachment.fileURL)
                ?? NSItemProvider(object: attachment.fileURL as NSURL)
        }
        .contextMenu {
            chipContextMenu
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if attachment.isImage, let image = NSImage(contentsOf: attachment.fileURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
        } else if attachment.isPDF {
            Image(systemName: "doc.richtext")
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var chipContextMenu: some View {
        Button {
            NSWorkspace.shared.open(attachment.fileURL)
        } label: {
            Label("Open", systemImage: "arrow.up.right.square")
        }

        Button {
            NSWorkspace.shared.activateFileViewerSelecting([attachment.fileURL])
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }

        Divider()

        if attachment.isImage, let image = NSImage(contentsOf: attachment.fileURL) {
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([image])
            } label: {
                Label("Copy Image", systemImage: "doc.on.doc")
            }
        }

        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(attachment.fileURL.path, forType: .string)
        } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            onRemove()
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }
}

// MARK: - Expanded Composer Overlay

struct ExpandedComposerOverlay: View {
    @Binding var messageText: String
    @Binding var draftAttachments: [DraftAttachment]
    @Binding var isPresented: Bool
    @Binding var isComposerDropTargeted: Bool

    let isBusy: Bool
    let canSendDraft: Bool
    let onSend: () -> Void
    let onDropFileURLs: ([URL]) -> Bool
    let onDropImages: ([NSImage]) -> Bool
    let onRemoveAttachment: (DraftAttachment) -> Void

    @State private var isEditorFocused = true

    private var wordCount: Int {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    private var characterCount: Int {
        messageText.count
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.15)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            panelContent
                .frame(maxWidth: 720, maxHeight: 560)
                .background {
                    RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)
                        .fill(.regularMaterial)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)
                        .stroke(JinSemanticColor.separator.opacity(0.45), lineWidth: JinStrokeWidth.hairline)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 8)
                .padding(40)
        }
    }

    private var panelContent: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider()
            panelAttachmentChips
            panelEditor
            Divider()
            panelFooter
        }
    }

    private var panelHeader: some View {
        HStack {
            Text("Compose")
                .font(.headline)

            Spacer()

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color.secondary.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, JinSpacing.large)
        .padding(.vertical, JinSpacing.medium)
    }

    @ViewBuilder
    private var panelAttachmentChips: some View {
        if !draftAttachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: JinSpacing.small) {
                    ForEach(draftAttachments) { attachment in
                        DraftAttachmentChip(
                            attachment: attachment,
                            onRemove: { onRemoveAttachment(attachment) }
                        )
                    }
                }
                .padding(.horizontal, JinSpacing.large)
                .padding(.vertical, JinSpacing.small)
            }
        }
    }

    private var panelEditor: some View {
        ZStack(alignment: .topLeading) {
            if messageText.isEmpty {
                Text("Type a message...")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
                    .padding(.leading, 6)
            }

            DroppableTextEditor(
                text: $messageText,
                isDropTargeted: $isComposerDropTargeted,
                isFocused: $isEditorFocused,
                font: NSFont.preferredFont(forTextStyle: .body),
                useCommandEnterToSubmit: true,
                onDropFileURLs: onDropFileURLs,
                onDropImages: onDropImages,
                onSubmit: {
                    guard canSendDraft, !isBusy else { return }
                    onSend()
                },
                onCancel: {
                    isPresented = false
                    return true
                }
            )
        }
        .padding(.horizontal, JinSpacing.large)
        .frame(maxHeight: .infinity)
    }

    private var panelFooter: some View {
        HStack(spacing: JinSpacing.small) {
            Text("\(wordCount) words \u{00B7} \(characterCount) characters")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            Spacer()

            Text("\u{2318}\u{21A9}")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button {
                guard canSendDraft, !isBusy else { return }
                onSend()
            } label: {
                HStack(spacing: 4) {
                    Text("Send")
                        .font(.body.weight(.medium))
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.body)
                }
                .foregroundStyle(canSendDraft && !isBusy ? Color.accentColor : .gray)
            }
            .buttonStyle(.plain)
            .disabled(!canSendDraft || isBusy)
        }
        .padding(.horizontal, JinSpacing.large)
        .padding(.vertical, JinSpacing.medium)
    }
}
