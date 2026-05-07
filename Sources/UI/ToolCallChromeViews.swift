import SwiftUI

struct ToolCallHeaderRow: View {
    let serverLabel: String
    let toolLabel: String
    let showsServerTag: Bool
    let status: ToolCallExecutionStatus
    let statusLabel: String
    let durationText: String?
    let statusStyle: ToolTimelinePresentationSupport.StatusVisualStyle
    @Binding var isExpanded: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: JinSpacing.small) {
            if showsServerTag {
                Text(serverLabel)
                    .jinTagStyle()
            }

            Text(toolLabel)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            ToolTimelinePresentationSupport.InlineStatusLabel(
                status: status,
                label: statusLabel,
                detail: durationText,
                textColor: statusStyle.text,
                accentColor: statusStyle.accent
            )

            Button {
                withAnimation(.spring(duration: 0.25, bounce: 0)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(JinIconButtonStyle())
        }
    }
}

struct ToolCallArgumentSummaryView: View {
    let argumentSummary: String

    var body: some View {
        Text("-> \(argumentSummary)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .textSelection(.enabled)
    }
}

struct ToolCallExpandedContentView: View {
    let formattedArgumentsJSON: String?
    let toolResult: ToolResult?
    let signature: String?

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            argumentsBlock

            resultSection

            signatureBlock
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var argumentsBlock: some View {
        ToolCallCodeBlockView(
            title: "Arguments",
            text: formattedArgumentsJSON ?? "{}",
            showsCopyButton: true
        )
    }

    @ViewBuilder
    private var resultSection: some View {
        if let toolResult {
            ToolCallCodeBlockView(
                title: toolResult.isError ? "Error" : "Output",
                text: toolResult.content,
                showsCopyButton: true
            )

            if let rawOutputPath = toolResult.rawOutputPath {
                ToolOutputFileActionRowView(rawOutputPath: rawOutputPath)
            }
        } else {
            waitingForResultCallout
        }
    }

    private var waitingForResultCallout: some View {
        Text("Waiting for tool result...")
            .jinInfoCallout()
    }

    @ViewBuilder
    private var signatureBlock: some View {
        if let signature, !signature.isEmpty {
            ToolCallCodeBlockView(title: "Signature", text: signature)
        }
    }
}

struct ToolCallCodeBlockView: View {
    let title: String
    let text: String
    var showsCopyButton: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            codeBlockHeader
            codeContent
        }
        .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
        .overlay(codeBlockBorder)
    }

    private var codeBlockHeader: some View {
        HStack {
            headerTitle
            Spacer(minLength: 0)
            copyButton
        }
        .padding(.horizontal, JinSpacing.medium - 2)
        .padding(.vertical, JinSpacing.xSmall)
        .background(JinSemanticColor.subtleSurfaceStrong)
        .overlay(alignment: .bottom) {
            headerSeparator
        }
    }

    private var headerTitle: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var copyButton: some View {
        if showsCopyButton {
            CopyToPasteboardButton(
                text: text,
                helpText: "Copy \(title.lowercased())",
                copiedHelpText: "\(title) copied",
                useProminentStyle: false
            )
        }
    }

    private var headerSeparator: some View {
        Rectangle()
            .fill(JinSemanticColor.separator.opacity(0.55))
            .frame(height: JinStrokeWidth.hairline)
    }

    private var codeContent: some View {
        ScrollView {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 168)
        .padding(.horizontal, JinSpacing.medium - 2)
        .padding(.vertical, JinSpacing.small)
        .background(JinSemanticColor.raisedSurface)
    }

    private var codeBlockBorder: some View {
        RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
            .stroke(JinSemanticColor.separator.opacity(0.75), lineWidth: JinStrokeWidth.hairline)
    }
}
