import SwiftUI
import AppKit

// MARK: - Code Execution Entry

struct CodeExecutionEntryView: View {
    let activity: CodeExecutionActivity
    let entryIndex: Int
    let showsConnectorAbove: Bool
    let showsConnectorBelow: Bool

    @State private var isRunningPulse = false

    private var executionStatus: CodeExecVisualStatus {
        switch activity.status {
        case .inProgress, .writingCode, .interpreting:
            return .running
        case .completed:
            return .success
        case .failed, .incomplete:
            return .error
        case .unknown:
            return .neutral
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: JinSpacing.small) {
            timelineRail

            VStack(alignment: .leading, spacing: JinSpacing.small) {
                entryHeader
                entryBody
            }
            .padding(.horizontal, JinSpacing.medium)
            .padding(.vertical, JinSpacing.small)
            .jinSurface(.neutral, cornerRadius: JinRadius.small)
        }
        .animation(.spring(duration: 0.25, bounce: 0), value: executionStatus)
        .onAppear {
            updatePulseAnimation(for: executionStatus)
        }
        .onChange(of: executionStatus) { _, newValue in
            updatePulseAnimation(for: newValue)
        }
    }

    // MARK: - Timeline Rail

    @ViewBuilder
    private var timelineRail: some View {
        VStack(spacing: 2) {
            Rectangle()
                .fill(JinSemanticColor.separator.opacity(0.7))
                .frame(width: JinStrokeWidth.regular, height: 12)
                .opacity(showsConnectorAbove ? 1 : 0)

            statusNode

            Rectangle()
                .fill(JinSemanticColor.separator.opacity(0.7))
                .frame(width: JinStrokeWidth.regular, height: 12)
                .opacity(showsConnectorBelow ? 1 : 0)
        }
        .frame(width: 16)
        .padding(.top, JinSpacing.xSmall)
    }

    @ViewBuilder
    private var statusNode: some View {
        let style = visualStyle

        ZStack {
            Circle()
                .fill(style.nodeBackground)
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .stroke(style.nodeBorder, lineWidth: 0.75)
                )

            switch executionStatus {
            case .running:
                Circle()
                    .fill(style.accent)
                    .frame(width: 6, height: 6)
                    .scaleEffect(isRunningPulse ? 1.4 : 0.85)
                    .opacity(isRunningPulse ? 0.35 : 1)
                    .animation(
                        .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
                        value: isRunningPulse
                    )
            case .success:
                Image(systemName: "checkmark")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(style.accent)
            case .error:
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(style.accent)
            case .neutral:
                Image(systemName: "questionmark")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(style.accent)
            }
        }
    }

    // MARK: - Entry Header

    private var entryHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: JinSpacing.small) {
            Image(systemName: "terminal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(visualStyle.accent)
                .frame(width: 16, height: 16)

            Text("Execution \(entryIndex + 1)")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let returnCode = activity.returnCode, shouldShowReturnCode {
                Text("exit \(returnCode)")
                    .jinTagStyle(
                        foreground: returnCode == 0
                            ? .secondary
                            : Color(nsColor: .systemOrange).opacity(0.95)
                    )
            }

            statusPill
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        let style = visualStyle

        HStack(spacing: 6) {
            if executionStatus == .running {
                Circle()
                    .fill(style.accent)
                    .frame(width: 4.5, height: 4.5)
            } else {
                switch executionStatus {
                case .success:
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(style.accent)
                case .error:
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(style.accent)
                case .neutral:
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(style.accent)
                case .running:
                    EmptyView()
                }
            }

            Text(statusLabel)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(style.text)
        .lineLimit(1)
    }

    private var statusLabel: String {
        switch activity.status {
        case .inProgress: return "Starting..."
        case .writingCode: return "Writing..."
        case .interpreting: return "Running..."
        case .completed: return "Done"
        case .failed: return "Failed"
        case .incomplete: return "Incomplete"
        case .unknown(let rawValue):
            return rawValue.isEmpty ? "Unknown" : rawValue
        }
    }

    // MARK: - Entry Body

    @ViewBuilder
    private var entryBody: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            if let code = activity.code, !code.isEmpty {
                CodeExecContentBlockView(
                    title: "Generated Code",
                    text: code,
                    style: .code,
                    badgeText: codeBadgeText,
                    language: codeLanguage
                )
            }

            if let containerID = activity.containerID, !containerID.isEmpty {
                metadataBlock(
                    title: "Container",
                    value: containerID,
                    copyHelpText: "Copy container ID"
                )
            }

            if let stdout = activity.stdout, !stdout.isEmpty {
                CodeExecContentBlockView(
                    title: "Output",
                    text: stdout,
                    style: .output
                )
            }

            if let stderr = activity.stderr, !stderr.isEmpty {
                CodeExecContentBlockView(
                    title: "Error",
                    text: stderr,
                    style: .error
                )
            }

            if let outputImages = activity.outputImages, !outputImages.isEmpty {
                Text(outputImages.count == 1 ? "Generated 1 image output" : "Generated \(outputImages.count) image outputs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, JinSpacing.medium)
                    .padding(.vertical, JinSpacing.small)
                    .jinSurface(.subtle, cornerRadius: JinRadius.small)
            }

            if let outputFiles = activity.outputFiles, !outputFiles.isEmpty {
                outputFilesBlock(outputFiles)
            }

            if !hasDisplayableContent {
                statusPlaceholder
            }
        }
    }

    // MARK: - Status Placeholder

    @ViewBuilder
    private var statusPlaceholder: some View {
        if executionStatus == .running {
            HStack(spacing: JinSpacing.small) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 14, height: 14)

                Text(activity.status == .writingCode ? "Writing code..." : activity.status == .interpreting ? "Running code..." : "Starting...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, JinSpacing.medium)
            .padding(.vertical, JinSpacing.small)
            .jinSurface(.subtle, cornerRadius: JinRadius.small)
        }
    }

    // MARK: - Visual Style

    private var visualStyle: CodeExecVisualStyle {
        switch executionStatus {
        case .running:
            return CodeExecVisualStyle(
                accent: .secondary,
                text: .secondary,
                nodeBackground: Color.primary.opacity(0.08),
                nodeBorder: JinSemanticColor.separator.opacity(0.72)
            )
        case .success:
            return CodeExecVisualStyle(
                accent: Color(nsColor: .systemGreen).opacity(0.88),
                text: Color(nsColor: .systemGreen).opacity(0.88),
                nodeBackground: Color(nsColor: .systemGreen).opacity(0.11),
                nodeBorder: Color(nsColor: .systemGreen).opacity(0.26)
            )
        case .error:
            return CodeExecVisualStyle(
                accent: Color(nsColor: .systemOrange).opacity(0.95),
                text: Color(nsColor: .systemOrange).opacity(0.95),
                nodeBackground: Color(nsColor: .systemOrange).opacity(0.14),
                nodeBorder: Color(nsColor: .systemOrange).opacity(0.36)
            )
        case .neutral:
            return CodeExecVisualStyle(
                accent: Color.secondary.opacity(0.85),
                text: Color.secondary.opacity(0.85),
                nodeBackground: Color.primary.opacity(0.05),
                nodeBorder: JinSemanticColor.separator.opacity(0.6)
            )
        }
    }

    private var hasDisplayableContent: Bool {
        let hasCode = !(activity.code?.isEmpty ?? true)
        let hasStdout = !(activity.stdout?.isEmpty ?? true)
        let hasStderr = !(activity.stderr?.isEmpty ?? true)
        let hasImages = !(activity.outputImages?.isEmpty ?? true)
        let hasFiles = !(activity.outputFiles?.isEmpty ?? true)
        let hasContainer = !(activity.containerID?.isEmpty ?? true)
        return hasCode || hasStdout || hasStderr || hasImages || hasFiles || hasContainer
    }

    private var shouldShowReturnCode: Bool {
        activity.status == .completed || activity.status == .failed || activity.status == .incomplete
    }

    private var codeLanguage: CodeExecCodeLanguage? {
        guard let code = activity.code, !code.isEmpty else { return nil }
        return CodeExecCodeLanguage.infer(from: code)
    }

    private var codeBadgeText: String? {
        guard let codeLanguage, codeLanguage != .generic else { return nil }
        return codeLanguage.badgeLabel
    }

    private func updatePulseAnimation(for status: CodeExecVisualStatus) {
        isRunningPulse = status == .running
    }

    @ViewBuilder
    private func metadataBlock(title: String, value: String, copyHelpText: String) -> some View {
        HStack(alignment: .center, spacing: JinSpacing.small) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(1)

            Spacer(minLength: 0)

            CopyToPasteboardButton(
                text: value,
                helpText: copyHelpText,
                useProminentStyle: false
            )
        }
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, JinSpacing.small)
        .jinSurface(.subtle, cornerRadius: JinRadius.small)
    }

    @ViewBuilder
    private func outputFilesBlock(_ outputFiles: [CodeExecutionOutputFile]) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Text(outputFiles.count == 1 ? "Generated 1 file output" : "Generated \(outputFiles.count) file outputs")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(outputFiles, id: \.self) { outputFile in
                metadataBlock(
                    title: "File ID",
                    value: outputFile.id,
                    copyHelpText: "Copy file ID"
                )
            }
        }
    }
}

// MARK: - Visual Types

enum CodeExecVisualStatus: Equatable {
    case running
    case success
    case error
    case neutral
}

struct CodeExecVisualStyle {
    let accent: Color
    let text: Color
    let nodeBackground: Color
    let nodeBorder: Color
}
