import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ArtifactWorkspaceView: View {
    let catalog: ArtifactCatalog
    @Binding var selectedArtifactID: String?
    @Binding var selectedArtifactVersion: Int?
    let onClose: () -> Void
    @State private var displayMode: ArtifactWorkspaceSupport.DisplayMode = .preview
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
                            NativeMarkdownView(markdownText: ArtifactWorkspaceSupport.highlightedCodeMarkdown(for: artifact))
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
        ArtifactWorkspaceSupport.selectedArtifact(
            in: catalog,
            selectedArtifactID: selectedArtifactID,
            selectedArtifactVersion: selectedArtifactVersion
        )
    }

    private var resolvedArtifactID: String? {
        ArtifactWorkspaceSupport.resolvedArtifactID(
            in: catalog,
            selectedArtifactID: selectedArtifactID
        )
    }

    private var availableArtifactIDs: [String] {
        catalog.orderedArtifactIDs
    }

    private var availableVersions: [RenderedArtifactVersion] {
        ArtifactWorkspaceSupport.availableVersions(
            in: catalog,
            selectedArtifactID: selectedArtifactID
        )
    }

    private var showsArtifactPicker: Bool {
        ArtifactWorkspaceSupport.showsArtifactPicker(in: catalog)
    }

    private var showsVersionPicker: Bool {
        ArtifactWorkspaceSupport.showsVersionPicker(for: availableVersions)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Group {
                    if showsArtifactPicker {
                        Picker("Artifact", selection: artifactSelectionBinding) {
                            ForEach(availableArtifactIDs, id: \.self) { artifactID in
                                Text(catalog.latestVersion(for: artifactID)?.title ?? artifactID).tag(
                                    Optional(artifactID))
                            }
                        }
                        .labelsHidden()
                    } else {
                        Text(selectedArtifact?.title ?? "Artifacts")
                            .font(.headline)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                if let artifact = selectedArtifact {
                    Button {
                        copySource(artifact.content)
                    } label: {
                        Image(systemName: isShowingCopyFeedback ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(JinIconButtonStyle(showBackground: false))
                    .help(isShowingCopyFeedback ? "Copied" : "Copy source")
                    .accessibilityLabel("Copy source")

                    Button {
                        export(artifact)
                    } label: {
                        Image(systemName: isShowingSaveFeedback ? "checkmark" : "square.and.arrow.down")
                    }
                    .buttonStyle(JinIconButtonStyle(showBackground: false))
                    .help(isShowingSaveFeedback ? "Saved" : "Save artifact")
                    .accessibilityLabel("Save artifact")
                }

                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(JinIconButtonStyle(showBackground: false))
                    .help("Close artifact pane")
                    .accessibilityLabel("Close artifact pane")
            }

            HStack(spacing: 8) {
                if let artifact = selectedArtifact {
                    Text(artifact.contentType.rawValue.uppercased())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if showsVersionPicker {
                    Picker("Revision", selection: versionSelectionBinding) {
                        ForEach(availableVersions, id: \.id) { version in
                            Text("Version \(version.version)").tag(Optional(version.version))
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                }
                Spacer(minLength: 0)
                Picker("Display", selection: $displayMode) {
                    ForEach(ArtifactWorkspaceSupport.DisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
            }
        }
        .padding(12)
    }

    private var artifactSelectionBinding: Binding<String?> {
        Binding(
            get: { resolvedArtifactID },
            set: { newValue in
                let selection = ArtifactWorkspaceSupport.selectionAfterArtifactChange(
                    newValue,
                    in: catalog
                )
                selectedArtifactID = selection.artifactID
                selectedArtifactVersion = selection.version
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
        let selection = ArtifactWorkspaceSupport.selectionAfterSync(
            in: catalog,
            selectedArtifactID: selectedArtifactID,
            selectedArtifactVersion: selectedArtifactVersion
        )
        selectedArtifactID = selection.artifactID
        selectedArtifactVersion = selection.version
    }

    private func copySource(_ source: String) {
        PasteboardSupport.writeString(source)
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
        do {
            try artifact.content.data(using: .utf8)?.write(to: url, options: .atomic)
            pulseFeedback(.save)
        } catch {
            // Write failed — skip save feedback
        }
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
        ArtifactWorkspaceSupport.filenameStem(
            for: artifact,
            showsVersionPicker: showsVersionPicker
        )
    }
}
