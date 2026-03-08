import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ArtifactWorkspaceView: View {
    private enum DisplayMode: String, CaseIterable, Identifiable {
        case preview
        case code

        var id: String { rawValue }

        var title: String {
            switch self {
            case .preview:
                return "Preview"
            case .code:
                return "Code"
            }
        }
    }

    let catalog: ArtifactCatalog
    @Binding var selectedArtifactID: String?
    @Binding var selectedArtifactVersion: Int?
    let onClose: () -> Void
    @State private var displayMode: DisplayMode = .preview
    @State private var isShowingCopyFeedback = false
    @State private var isShowingSaveFeedback = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(JinSemanticColor.separator.opacity(0.35))

            Group {
                if let artifact = selectedArtifact {
                    if displayMode == .preview {
                        ArtifactWebRenderer(artifact: artifact)
                    } else {
                        ScrollView {
                            MarkdownWebRenderer(markdownText: highlightedCodeMarkdown(for: artifact))
                                .padding(14)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Artifact Selected",
                        systemImage: "square.stack.3d.up",
                        description: Text("Artifacts generated in this thread will appear here.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(JinSemanticColor.detailSurface)
        }
        .frame(minWidth: 380, idealWidth: 500, maxWidth: 820)
        .background(JinSemanticColor.detailSurface)
        .onAppear(perform: syncSelection)
        .onChange(of: catalog.orderedArtifactIDs) { _, _ in
            syncSelection()
        }
        .onChange(of: selectedArtifactID) { _, _ in
            syncSelection()
        }
    }

    private var selectedArtifact: RenderedArtifactVersion? {
        guard let artifactID = resolvedArtifactID else { return nil }
        return catalog.version(artifactID: artifactID, version: selectedArtifactVersion)
    }

    private var resolvedArtifactID: String? {
        if let selectedArtifactID,
           !catalog.versions(for: selectedArtifactID).isEmpty {
            return selectedArtifactID
        }
        return catalog.latestVersion?.artifactID
    }

    private var availableArtifactIDs: [String] {
        catalog.orderedArtifactIDs
    }

    private var availableVersions: [RenderedArtifactVersion] {
        guard let resolvedArtifactID else { return [] }
        return catalog.versions(for: resolvedArtifactID)
    }

    private var showsArtifactPicker: Bool {
        availableArtifactIDs.count > 1
    }

    private var showsVersionPicker: Bool {
        availableVersions.count > 1
    }

    private var header: some View {
        HStack(spacing: JinSpacing.small) {
            VStack(alignment: .leading, spacing: 4) {
                if showsArtifactPicker {
                    Picker("Artifact", selection: artifactSelectionBinding) {
                        ForEach(availableArtifactIDs, id: \.self) { artifactID in
                            let title = catalog.latestVersion(for: artifactID)?.title ?? artifactID
                            Text(title).tag(Optional(artifactID))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220, alignment: .leading)
                } else {
                    Text(selectedArtifact?.title ?? "Artifacts")
                        .font(.headline)
                        .lineLimit(1)
                }

                HStack(spacing: JinSpacing.xSmall) {
                    if let artifact = selectedArtifact {
                        ArtifactTypeBadge(contentType: artifact.contentType)
                    }

                    if showsVersionPicker, let artifact = selectedArtifact {
                        Text("v\(artifact.version)")
                            .jinTagStyle()
                    }
                }
            }

            Spacer(minLength: 0)

            Picker("", selection: $displayMode) {
                ForEach(DisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 150)

            if showsVersionPicker {
                Picker("Revision", selection: versionSelectionBinding) {
                    ForEach(availableVersions, id: \.id) { version in
                        Text("v\(version.version)").tag(Optional(version.version))
                    }
                }
                .labelsHidden()
                .frame(width: 72)
            }

            if let artifact = selectedArtifact {
                Button {
                    copySource(artifact.content)
                } label: {
                    Image(systemName: isShowingCopyFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isShowingCopyFeedback ? Color.accentColor : Color.primary)
                }
                .buttonStyle(JinIconButtonStyle(isActive: isShowingCopyFeedback, accentColor: .accentColor))
                .help(isShowingCopyFeedback ? "Copied" : "Copy source")

                Button {
                    export(artifact)
                } label: {
                    Image(systemName: isShowingSaveFeedback ? "checkmark" : "arrow.down.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isShowingSaveFeedback ? Color.accentColor : Color.primary)
                }
                .buttonStyle(JinIconButtonStyle(isActive: isShowingSaveFeedback, accentColor: .accentColor))
                .help(isShowingSaveFeedback ? "Saved" : "Save artifact")
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(JinIconButtonStyle(showBackground: false))
            .help("Close artifact pane")
        }
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, 12)
    }

    private var artifactSelectionBinding: Binding<String?> {
        Binding(
            get: { resolvedArtifactID },
            set: { newValue in
                selectedArtifactID = newValue
                selectedArtifactVersion = catalog.latestVersion(for: newValue ?? "")?.version
            }
        )
    }

    private var versionSelectionBinding: Binding<Int?> {
        Binding(
            get: { selectedArtifact?.version },
            set: { newValue in
                selectedArtifactVersion = newValue
            }
        )
    }

    private func syncSelection() {
        guard let latest = catalog.latestVersion else {
            selectedArtifactID = nil
            selectedArtifactVersion = nil
            return
        }

        if let currentID = selectedArtifactID,
           catalog.version(artifactID: currentID, version: selectedArtifactVersion) != nil {
            return
        }

        selectedArtifactID = latest.artifactID
        selectedArtifactVersion = latest.version
    }

    private func copySource(_ source: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(source, forType: .string)
        pulseFeedback(.copy)
    }

    private func export(_ artifact: RenderedArtifactVersion) {
        let panel = NSSavePanel()
        panel.title = "Save Artifact"
        panel.prompt = "Save"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = filenameStem(for: artifact)
        if let contentType = UTType(filenameExtension: artifact.contentType.fileExtension) {
            panel.allowedContentTypes = [contentType]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? artifact.content.data(using: .utf8)?.write(to: url, options: .atomic)
        pulseFeedback(.save)
    }

    private enum FeedbackKind {
        case copy
        case save
    }

    private func pulseFeedback(_ kind: FeedbackKind) {
        switch kind {
        case .copy:
            isShowingCopyFeedback = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                isShowingCopyFeedback = false
            }
        case .save:
            isShowingSaveFeedback = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                isShowingSaveFeedback = false
            }
        }
    }

    private func filenameStem(for artifact: RenderedArtifactVersion) -> String {
        let fallback = artifact.artifactID.isEmpty ? "artifact" : artifact.artifactID
        let base = artifact.title.isEmpty ? fallback : artifact.title
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleanedScalars = base.unicodeScalars.map { invalid.contains($0) ? "-" : String($0) }
        let cleaned = cleanedScalars.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let name = cleaned.isEmpty ? fallback : cleaned
        if showsVersionPicker {
            return "\(name)-v\(artifact.version)"
        }
        return name
    }

    private func highlightedCodeMarkdown(for artifact: RenderedArtifactVersion) -> String {
        let fenceLength = max(3, maximumBacktickRunLength(in: artifact.content) + 1)
        let fence = String(repeating: "`", count: fenceLength)
        return "\(fence)\(artifact.contentType.codeFenceLanguage)\n\(artifact.content)\n\(fence)"
    }

    private func maximumBacktickRunLength(in text: String) -> Int {
        var maximum = 0
        var current = 0
        for character in text {
            if character == "`" {
                current += 1
                maximum = max(maximum, current)
            } else {
                current = 0
            }
        }
        return maximum
    }
}
