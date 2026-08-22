import AppKit
import SwiftUI

/// Draft chip for the composer's source-video URL. Deliberately shaped like
/// `DraftAttachmentChip` so a source video reads as "one more thing carried by
/// this turn" instead of a second input field stacked on the real one.
struct ComposerRemoteVideoURLChip: View {
    let urlText: String
    let onRemove: () -> Void

    private static let maxLabelWidth: CGFloat = 220

    private var label: String {
        ComposerRemoteVideoURLSupport.compactLabel(for: urlText)
    }

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            Image(systemName: "video.badge.plus")
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)

            Text(label)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: Self.maxLabelWidth, alignment: .leading)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove source video URL")
        }
        .padding(.horizontal, JinSpacing.medium - 2)
        .padding(.vertical, JinSpacing.xSmall + 2)
        .jinSurface(.neutral, cornerRadius: JinRadius.medium)
        .help(urlText)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Source video \(label)")
        .contextMenu {
            Button {
                PasteboardSupport.writeString(urlText)
            } label: {
                Label("Copy URL", systemImage: "doc.on.doc")
            }

            if let url = URL(string: urlText) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open in Browser", systemImage: "arrow.up.right.square")
                }
            }

            Divider()

            Button(role: .destructive, action: onRemove) {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}

/// Owns the popover flag *per mounted controls row*. It cannot live on
/// `ChatView`: the compact composer stays mounted (`opacity(0)` at
/// `ChatView+FloatingComposer.swift`) while the expanded composer sheet is up,
/// so two `composerControlsRow()` instances are alive at once and one shared
/// `isPresented` would drive two popover anchors. Same reason
/// `ContextUsageIndicatorView` keeps its own flag.
struct ComposerRemoteVideoURLPopoverHost<Control: View>: View {
    let urlText: String
    let onCommit: (String) -> Void
    let onClear: () -> Void
    @ViewBuilder let control: (@escaping () -> Void) -> Control

    @State private var isEditorPresented = false

    var body: some View {
        control { isEditorPresented = true }
            // The composer hugs the bottom edge, so ask for the arrow on the
            // anchor's top and let AppKit re-flip if it runs out of room.
            .popover(isPresented: $isEditorPresented, arrowEdge: .top) {
                ComposerRemoteVideoURLEditor(
                    initialURLText: urlText,
                    onCancel: { isEditorPresented = false },
                    onClear: {
                        onClear()
                        isEditorPresented = false
                    },
                    onCommit: { committed in
                        onCommit(committed)
                        isEditorPresented = false
                    }
                )
            }
    }
}

/// Single-field editor for the source-video URL, shaped like a stock macOS
/// mini-dialog: one labelled field over one right-aligned button row. The
/// guidance lives in the placeholder rather than a standing hint line — a
/// permanent sentence pushed the popover wide and stranded the action button
/// on a line of its own.
///
/// The in-flight text lives in this view's own `@State`; the caller receives
/// the value exactly once, on commit — never per keystroke, so typing a URL
/// cannot invalidate the chat timeline.
struct ComposerRemoteVideoURLEditor: View {
    let initialURLText: String
    let onCancel: () -> Void
    let onClear: () -> Void
    let onCommit: (String) -> Void

    @State private var draft: String
    @State private var errorMessage: String?
    @FocusState private var isFieldFocused: Bool

    private static let fieldWidth: CGFloat = 300

    init(
        initialURLText: String,
        onCancel: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onCommit: @escaping (String) -> Void
    ) {
        self.initialURLText = initialURLText
        self.onCancel = onCancel
        self.onClear = onClear
        self.onCommit = onCommit
        _draft = State(initialValue: initialURLText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Text("Source Video URL")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("https://example.com/clip.mp4", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .focused($isFieldFocused)
                // Return commits. Do not also mark "Set" as the default
                // action — inside a popover both fire and commit twice.
                .onSubmit(commit)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: JinSpacing.small) {
                if initialURLText.trimmedNonEmpty != nil {
                    Button("Remove", action: onClear)
                }

                Spacer(minLength: 0)

                // Paired with Set so the footer reads as a dialog row. A lone
                // prominent button floating bottom-right looks arbitrary.
                Button("Cancel", action: onCancel)

                Button("Set", action: commit)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 2)
        }
        .frame(width: Self.fieldWidth)
        .padding(JinSpacing.medium)
        .onChange(of: draft) { _, _ in errorMessage = nil }
        .onAppear { isFieldFocused = true }
    }

    private func commit() {
        let value = draft.trimmed
        if let message = ComposerRemoteVideoURLSupport.validationErrorMessage(for: value) {
            errorMessage = message
            return
        }
        onCommit(value)
    }
}
