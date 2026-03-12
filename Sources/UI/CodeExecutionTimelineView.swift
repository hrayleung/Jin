import SwiftUI
import AppKit

/// Displays a timeline of code execution activities from provider-native code execution tools
/// (OpenAI Code Interpreter, Anthropic Code Execution, xAI Code Interpreter).
struct CodeExecutionTimelineView: View {
    let activities: [CodeExecutionActivity]
    let isStreaming: Bool

    @State private var isExpanded: Bool

    init(activities: [CodeExecutionActivity], isStreaming: Bool) {
        self.activities = activities
        self.isStreaming = isStreaming
        let mode = Self.resolveDisplayMode()
        if isStreaming {
            _isExpanded = State(initialValue: mode.startsExpandedDuringStreaming)
        } else {
            _isExpanded = State(initialValue: mode.startsExpandedOnComplete)
        }
    }

    var body: some View {
        if !activities.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                headerRow

                VStack(spacing: 0) {
                    if isExpanded {
                        expandedContent
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .clipped()
            }
            .padding(JinSpacing.small)
            .jinSurface(.subtleStrong, cornerRadius: JinRadius.medium)
            .clipped()
            .animation(.spring(duration: 0.25, bounce: 0), value: isExpanded)
            .animation(.easeInOut(duration: 0.2), value: animationSignature)
            .onChange(of: isStreaming) { _, streaming in
                if streaming {
                    let mode = Self.resolveDisplayMode()
                    if mode.startsExpandedDuringStreaming {
                        withAnimation(.spring(duration: 0.25, bounce: 0)) {
                            isExpanded = true
                        }
                    }
                } else {
                    let mode = Self.resolveDisplayMode()
                    if mode == .collapseOnComplete {
                        withAnimation(.spring(duration: 0.25, bounce: 0)) {
                            isExpanded = false
                        }
                    }
                }
            }
        }
    }

    private static func resolveDisplayMode() -> CodeExecutionDisplayMode {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKeys.codeExecutionDisplayMode) ?? ""
        return CodeExecutionDisplayMode(rawValue: raw) ?? .expanded
    }

    // MARK: - Header Row

    private var headerRow: some View {
        Button {
            withAnimation(.spring(duration: 0.25, bounce: 0)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: JinSpacing.small) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(headerTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isStreaming, hasActiveExecution {
                    ProgressView()
                        .scaleEffect(0.5)
                }

                if let compactStatus = compactStatusStyle {
                    HStack(spacing: 4) {
                        Image(systemName: compactStatus.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(compactStatus.text)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(compactStatus.color)
                    .lineLimit(1)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, JinSpacing.small)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                CodeExecutionEntryView(
                    activity: activity,
                    entryIndex: index,
                    showsConnectorAbove: index > 0,
                    showsConnectorBelow: index < activities.count - 1
                )
            }
        }
        .padding(.horizontal, JinSpacing.small)
        .padding(.top, JinSpacing.xSmall)
        .padding(.bottom, JinSpacing.xSmall)
    }

    // MARK: - Computed

    private var hasActiveExecution: Bool {
        activities.contains { activity in
            switch activity.status {
            case .inProgress, .writingCode, .interpreting:
                return true
            default:
                return false
            }
        }
    }

    private var headerTitle: String {
        if activities.count == 1 {
            return "Code Execution"
        }
        return "\(activities.count) Code Executions"
    }

    private var compactStatusStyle: (text: String, icon: String, color: Color)? {
        if hasActiveExecution {
            return nil
        }

        let failedCount = activities.filter { $0.status == .failed }.count
        let completedCount = activities.filter { $0.status == .completed }.count

        if failedCount > 0 {
            return (
                text: "Failed",
                icon: "xmark.circle",
                color: Color(nsColor: .systemOrange).opacity(0.95)
            )
        }
        if completedCount > 0 {
            return (
                text: "Done",
                icon: "checkmark.circle",
                color: Color(nsColor: .systemGreen).opacity(0.88)
            )
        }
        return nil
    }

    private var animationSignature: String {
        activities
            .map { "\($0.id):\($0.status)" }
            .joined(separator: "|")
    }
}

// MARK: - Code Execution Entry

private struct CodeExecutionEntryView: View {
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

private enum CodeExecVisualStatus: Equatable {
    case running
    case success
    case error
    case neutral
}

private struct CodeExecVisualStyle {
    let accent: Color
    let text: Color
    let nodeBackground: Color
    let nodeBorder: Color
}

// MARK: - Content Blocks

private struct CodeExecContentBlockView: View {
    let title: String
    let text: String
    let style: CodeExecContentBlockStyle
    let badgeText: String?

    private let lineCount: Int
    private let longestLineLength: Int
    private let highlightedCode: AttributedString?
    private let collapsedHeight: CGFloat = 176
    private let expandedHeight: CGFloat = 320

    @State private var isExpanded = false
    @State private var scrollViewWidth: CGFloat = 0

    init(
        title: String,
        text: String,
        style: CodeExecContentBlockStyle,
        badgeText: String? = nil,
        language: CodeExecCodeLanguage? = nil
    ) {
        self.title = title
        self.text = text
        self.style = style
        self.badgeText = badgeText

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        self.lineCount = max(lines.count, 1)
        self.longestLineLength = lines.map(\.count).max() ?? text.count

        if style.usesSyntaxHighlighting {
            self.highlightedCode = CodeExecSyntaxHighlighter.highlighted(text, language: language)
        } else {
            self.highlightedCode = nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: JinSpacing.small) {
                Image(systemName: style.iconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(style.iconColor)

                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(style.titleColor)

                if let badgeText, !badgeText.isEmpty {
                    Text(badgeText)
                        .jinTagStyle(foreground: style.badgeColor)
                }

                Spacer(minLength: 0)

                if showsExpandControl {
                    Button(isExpanded ? "Show Less" : "Show More") {
                        withAnimation(.spring(duration: 0.25, bounce: 0)) {
                            isExpanded.toggle()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                }

                CopyToPasteboardButton(
                    text: text,
                    helpText: "Copy \(title.lowercased())",
                    copiedHelpText: "\(title) copied",
                    useProminentStyle: false
                )
            }
            .padding(.horizontal, JinSpacing.medium - 2)
            .padding(.vertical, JinSpacing.xSmall)
            .background(style.headerBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(JinSemanticColor.separator.opacity(0.55))
                    .frame(height: JinStrokeWidth.hairline)
            }

            ScrollView([.vertical, .horizontal], showsIndicators: true) {
                HStack(alignment: .top, spacing: JinSpacing.medium) {
                    if style.showsLineNumbers, let lineNumberText {
                        Text(lineNumberText)
                            .font(Self.contentFont)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.trailing)
                            .padding(.trailing, JinSpacing.small)
                            .overlay(alignment: .trailing) {
                                Rectangle()
                                    .fill(JinSemanticColor.separator.opacity(0.45))
                                    .frame(width: JinStrokeWidth.hairline)
                            }
                    }

                    renderedTextBody
                }
                .padding(.horizontal, JinSpacing.medium - 2)
                .padding(.vertical, JinSpacing.small)
                .frame(minWidth: scrollViewWidth, alignment: .leading)
            }
            .defaultScrollAnchor(.topLeading)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { scrollViewWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, w in scrollViewWidth = w }
                }
            )
            .frame(maxHeight: currentMaxHeight, alignment: .top)
            .background(style.bodyBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                .stroke(style.borderColor, lineWidth: JinStrokeWidth.hairline)
        )
    }

    @ViewBuilder
    private var renderedTextBody: some View {
        if let highlightedCode {
            Text(highlightedCode)
                .font(Self.contentFont)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
        } else {
            Text(text)
                .font(Self.contentFont)
                .foregroundStyle(style.textColor)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
        }
    }

    private var showsExpandControl: Bool {
        lineCount > 12 || longestLineLength > 120 || text.count > 800
    }

    private var currentMaxHeight: CGFloat? {
        guard showsExpandControl else { return nil }
        return isExpanded ? expandedHeight : collapsedHeight
    }

    private var lineNumberText: String? {
        guard lineCount > 1, lineCount <= 400 else { return nil }
        return (1...lineCount).map(String.init).joined(separator: "\n")
    }

    private static let contentFont = Font.system(.caption, design: .monospaced)
}

private struct CodeExecContentBlockStyle {
    let iconName: String
    let iconColor: Color
    let titleColor: Color
    let badgeColor: Color
    let textColor: Color
    let headerBackground: Color
    let bodyBackground: Color
    let borderColor: Color
    let showsLineNumbers: Bool
    let usesSyntaxHighlighting: Bool

    static let code = CodeExecContentBlockStyle(
        iconName: "chevron.left.forwardslash.chevron.right",
        iconColor: .secondary.opacity(0.75),
        titleColor: .secondary,
        badgeColor: .secondary,
        textColor: .primary.opacity(0.88),
        headerBackground: JinSemanticColor.subtleSurfaceStrong,
        bodyBackground: JinSemanticColor.raisedSurface,
        borderColor: JinSemanticColor.separator.opacity(0.75),
        showsLineNumbers: true,
        usesSyntaxHighlighting: true
    )

    static let output = CodeExecContentBlockStyle(
        iconName: "terminal",
        iconColor: .secondary.opacity(0.75),
        titleColor: .secondary,
        badgeColor: .secondary,
        textColor: .secondary,
        headerBackground: JinSemanticColor.subtleSurfaceStrong,
        bodyBackground: JinSemanticColor.raisedSurface,
        borderColor: JinSemanticColor.separator.opacity(0.75),
        showsLineNumbers: false,
        usesSyntaxHighlighting: false
    )

    static let error = CodeExecContentBlockStyle(
        iconName: "exclamationmark.triangle.fill",
        iconColor: Color(nsColor: .systemOrange).opacity(0.9),
        titleColor: Color(nsColor: .systemOrange).opacity(0.95),
        badgeColor: Color(nsColor: .systemOrange).opacity(0.95),
        textColor: Color(nsColor: .systemOrange).opacity(0.95),
        headerBackground: Color(nsColor: .systemOrange).opacity(0.1),
        bodyBackground: Color(nsColor: .systemOrange).opacity(0.045),
        borderColor: Color(nsColor: .systemOrange).opacity(0.24),
        showsLineNumbers: false,
        usesSyntaxHighlighting: false
    )
}

// MARK: - Code Language

private enum CodeExecCodeLanguage: Equatable {
    case python
    case javascript
    case shell
    case swift
    case generic

    var badgeLabel: String {
        switch self {
        case .python:
            return "Python"
        case .javascript:
            return "JavaScript"
        case .shell:
            return "Shell"
        case .swift:
            return "Swift"
        case .generic:
            return "Code"
        }
    }

    static func infer(from code: String) -> CodeExecCodeLanguage? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowercase = trimmed.lowercased()

        if trimmed.hasPrefix("#!/bin/bash") || trimmed.hasPrefix("#!/bin/sh") || lowercase.contains("echo ") && lowercase.contains("$") {
            return .shell
        }

        if lowercase.contains("import swiftui") || lowercase.contains("struct ") && lowercase.contains(": view") {
            return .swift
        }

        if lowercase.contains("console.log") || lowercase.contains("const ") || lowercase.contains("let ") || lowercase.contains("=>") {
            return .javascript
        }

        if lowercase.contains("import ") || lowercase.contains("print(") || lowercase.contains("def ") || lowercase.contains("plt.") {
            return .python
        }

        return .generic
    }
}

// MARK: - Syntax Highlighting

private enum CodeExecSyntaxHighlighter {
    private static let baseColor = NSColor.labelColor.withAlphaComponent(0.88)
    private static let keywordColor = NSColor.systemBlue.withAlphaComponent(0.9)
    private static let stringColor = NSColor.systemRed.withAlphaComponent(0.86)
    private static let commentColor = NSColor.secondaryLabelColor.withAlphaComponent(0.95)
    private static let numberColor = NSColor.systemPurple.withAlphaComponent(0.82)
    private static let functionColor = NSColor.systemTeal.withAlphaComponent(0.9)

    static func highlighted(_ text: String, language: CodeExecCodeLanguage?) -> AttributedString {
        guard !text.isEmpty else { return AttributedString("") }
        guard text.count <= 20_000 else { return AttributedString(text) }

        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .foregroundColor: baseColor
            ]
        )
        let fullRange = NSRange(location: 0, length: attributed.length)

        let functionPattern = #"(?m)\b([A-Za-z_][A-Za-z0-9_]*)\s*(?=\()"#
        apply(pattern: functionPattern, color: functionColor, to: attributed, range: fullRange)

        let keywordPattern = keywordPattern(for: language)
        apply(pattern: keywordPattern, color: keywordColor, to: attributed, range: fullRange)

        let numberPattern = #"(?<![\w.])\d+(?:\.\d+)?(?![\w.])"#
        apply(pattern: numberPattern, color: numberColor, to: attributed, range: fullRange)

        let stringPattern = #"(?s)\"\"\".*?\"\"\"|'''.*?'''|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#
        apply(pattern: stringPattern, color: stringColor, to: attributed, range: fullRange)

        let commentPattern = commentPattern(for: language)
        apply(pattern: commentPattern, color: commentColor, to: attributed, range: fullRange)

        return AttributedString(attributed)
    }

    private static func keywordPattern(for language: CodeExecCodeLanguage?) -> String {
        switch language {
        case .javascript:
            return #"\b(await|async|break|case|catch|class|const|continue|default|else|export|false|finally|for|from|function|if|import|in|let|new|null|return|switch|throw|true|try|typeof|undefined|var|while)\b"#
        case .shell:
            return #"\b(case|do|done|elif|else|esac|export|fi|for|function|if|in|local|return|then|unset|while)\b"#
        case .swift:
            return #"\b(actor|async|await|case|class|enum|extension|false|for|func|if|import|in|let|nil|private|protocol|return|self|struct|switch|throw|true|var|while)\b"#
        case .python, .generic, .none:
            return #"\b(and|as|assert|break|class|continue|def|del|elif|else|except|False|finally|for|from|if|import|in|is|lambda|None|nonlocal|not|or|pass|raise|return|True|try|while|with|yield)\b"#
        }
    }

    private static func commentPattern(for language: CodeExecCodeLanguage?) -> String {
        switch language {
        case .javascript, .swift:
            return #"(?m)//.*$|/\*[\s\S]*?\*/"#
        case .shell, .python, .generic, .none:
            return #"(?m)#.*$"#
        }
    }

    private static func apply(
        pattern: String,
        color: NSColor,
        to attributed: NSMutableAttributedString,
        range: NSRange
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let matches = regex.matches(in: attributed.string, options: [], range: range)
        for match in matches {
            attributed.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}
