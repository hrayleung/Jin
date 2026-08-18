import SwiftUI

struct PerMessageMCPChip: View {
    let name: String
    let onRemove: () -> Void

    private static let maxLabelWidth: CGFloat = 180

    var body: some View {
        HStack(spacing: JinSpacing.xSmall) {
            Text(name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: Self.maxLabelWidth, alignment: .leading)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, JinSpacing.medium - 2)
        .padding(.vertical, JinSpacing.xSmall + 2)
        .background(
            Capsule()
                .fill(JinSemanticColor.accentSurface)
        )
        .overlay(
            Capsule()
                .stroke(JinSemanticColor.selectedStroke, lineWidth: JinStrokeWidth.hairline)
        )
        .help(name)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
    }
}

/// Corner mark that does not change the 28pt icon layout. Counts and
/// 1–3 character tokens only — never a second row, never a long word.
struct ComposerControlBadge: View {
    let text: String
    let isActive: Bool
    let activeColor: Color

    var body: some View {
        Text(text)
            .font(.system(size: 7, weight: .bold, design: .rounded))
            .foregroundStyle(isActive ? activeColor : .secondary)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(
                Capsule()
                    .fill(JinSemanticColor.raisedSurface)
            )
            .overlay(
                Capsule()
                    .stroke(isActive ? activeColor.opacity(0.35) : JinSemanticColor.separator.opacity(0.5), lineWidth: 0.5)
            )
            .lineLimit(1)
            .fixedSize()
            .id(text)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transaction { transaction in
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
    }
}

struct ComposerControlIconLabel: View {
    let systemName: String
    let isActive: Bool
    let activeColor: Color

    init(
        systemName: String,
        isActive: Bool,
        activeColor: Color = .accentColor
    ) {
        self.systemName = systemName
        self.isActive = isActive
        self.activeColor = activeColor
    }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isActive ? activeColor : Color.secondary)
            .frame(width: JinControlMetrics.iconButtonHitSize, height: JinControlMetrics.iconButtonHitSize)
            .background(
                Circle()
                    .fill(isActive ? activeColor.opacity(0.14) : Color.clear)
            )
            .transaction { transaction in
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
    }
}

struct ComposerEditorSurface<Content: View>: View {
    let isFocused: Bool
    let isDropTargeted: Bool
    @ViewBuilder let content: () -> Content

    private var borderColor: Color {
        if isDropTargeted {
            return Color.accentColor.opacity(0.7)
        }
        if isFocused {
            return Color.accentColor.opacity(0.34)
        }
        return JinSemanticColor.borderEmphasized
    }

    private var shadowColor: Color {
        if isDropTargeted {
            return Color.accentColor.opacity(0.16)
        }
        if isFocused {
            return Color.accentColor.opacity(0.10)
        }
        return JinSemanticColor.shadowSubtle
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)

        VStack(alignment: .leading, spacing: JinSpacing.small) {
            content()
        }
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, JinSpacing.small + 2)
        .background {
            shape.fill(JinSemanticColor.textSurface)
        }
        .overlay(
            shape.stroke(
                borderColor,
                lineWidth: isDropTargeted ? JinStrokeWidth.emphasized : JinStrokeWidth.hairline
            )
        )
        .shadow(color: shadowColor, radius: isFocused || isDropTargeted ? 12 : 4, x: 0, y: isFocused || isDropTargeted ? 2 : 0)
        .animation(.easeInOut(duration: 0.14), value: isFocused)
        .animation(.easeInOut(duration: 0.14), value: isDropTargeted)
    }
}

struct ComposerStatusSummaryView: View {
    let isPreparingToSend: Bool
    let prepareToSendStatus: String?
    let isRecording: Bool
    let isTranscribing: Bool
    let recordingDurationText: String
    let transcribingStatusText: String

    @ViewBuilder
    var body: some View {
        if isPreparingToSend, let prepareToSendStatus {
            HStack(spacing: 8) {
                Image(systemName: "paperplane.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                Text(prepareToSendStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        } else if isRecording {
            HStack(spacing: 8) {
                Image(systemName: "record.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(width: 20, height: 20)
                Text("Recording\u{2026} \(recordingDurationText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        } else if isTranscribing {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                Text(transcribingStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

struct CollapsedComposerBar: View {
    let hasContent: Bool
    let onExpand: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)

        Button(action: onExpand) {
            HStack(spacing: JinSpacing.medium) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(JinSemanticColor.textTertiary)

                Text(hasContent ? "Continue typing\u{2026}" : "Type a message\u{2026}")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, JinSpacing.large)
            .padding(.vertical, 10)
            .frame(maxWidth: 800)
            .background {
                shape.fill(JinSemanticColor.raisedSurface)
            }
            .overlay(
                shape.stroke(JinSemanticColor.borderEmphasized, lineWidth: JinStrokeWidth.hairline)
            )
            .shadow(color: JinSemanticColor.shadowElevated, radius: 16, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show message composer")
        .accessibilityHint("Double-click to expand the message input area")
    }
}
