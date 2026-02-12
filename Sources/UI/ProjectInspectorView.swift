import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ProjectInspectorView: View {
    let project: ProjectEntity

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ProjectSettingsEditorView(project: project)
                .navigationTitle("Project Settings")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            dismiss()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 700, idealHeight: 800)
    }
}

private struct ProjectSettingsEditorView: View {
    @Bindable var project: ProjectEntity
    @Environment(\.modelContext) private var modelContext

    @State private var isFileImporterPresented = false
    @State private var isProcessingDocument = false
    @State private var documentError: String?
    @State private var showingDocumentError = false
    @State private var documentPendingDeletion: ProjectDocumentEntity?
    @State private var showingDeleteDocumentConfirmation = false

    @Query private var embeddingProviders: [EmbeddingProviderConfigEntity]
    @Query private var rerankProviders: [RerankProviderConfigEntity]

    var body: some View {
        Form {
            headerSection
            identitySection
            instructionsSection
            contextModeSection
            documentsSection

            if resolvedContextMode == .rag {
                ragSettingsSection
            }

            dangerZoneSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: supportedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .alert("Document Error", isPresented: $showingDocumentError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(documentError ?? "An unknown error occurred.")
        }
        .confirmationDialog(
            "Remove document?",
            isPresented: $showingDeleteDocumentConfirmation,
            presenting: documentPendingDeletion
        ) { document in
            Button("Remove", role: .destructive) {
                deleteDocument(document)
            }
        } message: { document in
            Text("Remove \"\(document.filename)\" from this project?")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var headerSection: some View {
        Section {
            HStack(alignment: .center, spacing: 16) {
                projectIcon
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 6) {
                    Text(projectDisplayName)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Documents shared across all conversations in this project.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .jinSurface(.raised, cornerRadius: JinRadius.medium)
        }
    }

    @ViewBuilder
    private var identitySection: some View {
        Section("Identity") {
            LabeledContent("Name") {
                TextField(text: nameBinding, prompt: Text("e.g., API Documentation")) {
                    EmptyView()
                }
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
            }

            LabeledContent("Icon") {
                TextField(text: iconBinding, prompt: Text("e.g., folder.fill")) {
                    EmptyView()
                }
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
            }

            LabeledContent("Description") {
                TextField(text: descriptionBinding, prompt: Text("e.g., Backend API specs and docs"), axis: .vertical) {
                    EmptyView()
                }
                .multilineTextAlignment(.trailing)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    @ViewBuilder
    private var instructionsSection: some View {
        Section("Project Instructions") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Custom instructions appended to the system prompt for conversations in this project.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: customInstructionBinding)
                    .font(.body)
                    .frame(minHeight: 80, maxHeight: 200)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
            }
        }
    }

    @ViewBuilder
    private var contextModeSection: some View {
        Section("Context Mode") {
            Picker("Mode", selection: contextModeBinding) {
                ForEach(ProjectContextMode.allCases, id: \.rawValue) { mode in
                    VStack(alignment: .leading) {
                        Text(mode.displayName)
                    }
                    .tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(resolvedContextMode.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            if resolvedContextMode == .rag && enabledEmbeddingProviders.isEmpty {
                HStack(spacing: JinSpacing.small) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("RAG mode requires an embedding provider. Configure one in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var documentsSection: some View {
        Section {
            if sortedDocuments.isEmpty {
                ContentUnavailableView {
                    Label("No Documents", systemImage: "doc.text")
                } description: {
                    Text("Add documents to provide context for conversations.")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, JinSpacing.large)
            } else {
                ForEach(sortedDocuments) { document in
                    ProjectDocumentRowView(document: document) {
                        documentPendingDeletion = document
                        showingDeleteDocumentConfirmation = true
                    }
                }
            }
        } header: {
            HStack {
                Text("Documents (\(readyDocumentCount)/\(project.documents.count))")
                Spacer()
                if totalTokenEstimate > 0 {
                    Text("~\(formattedTokenCount) tokens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    isFileImporterPresented = true
                } label: {
                    Label("Add Document", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(isProcessingDocument)
            }
        }
    }

    @ViewBuilder
    private var ragSettingsSection: some View {
        Section("RAG Settings") {
            Picker("Embedding Provider", selection: embeddingProviderIDBinding) {
                Text("None").tag(String?.none)
                ForEach(enabledEmbeddingProviders) { provider in
                    Text(provider.name).tag(Optional(provider.id))
                }
            }

            if project.embeddingProviderID != nil {
                Picker("Embedding Model", selection: embeddingModelIDBinding) {
                    Text("Default").tag(String?.none)
                }
            }

            Picker("Rerank Provider", selection: rerankProviderIDBinding) {
                Text("None (skip reranking)").tag(String?.none)
                ForEach(enabledRerankProviders) { provider in
                    Text(provider.name).tag(Optional(provider.id))
                }
            }

            if project.rerankProviderID != nil {
                Picker("Rerank Model", selection: rerankModelIDBinding) {
                    Text("Default").tag(String?.none)
                }
            }

            HStack {
                Text("Index Status")
                Spacer()
                let indexedCount = project.documents.filter { $0.chunkCount > 0 }.count
                let totalChunks = project.documents.reduce(0) { $0 + $1.chunkCount }
                Text("\(indexedCount) docs, \(totalChunks) chunks")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var dangerZoneSection: some View {
        Section("Info") {
            LabeledContent("Project ID") {
                Text(project.id)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            LabeledContent("Created") {
                Text(project.createdAt, format: .dateTime)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Computed

    private var projectDisplayName: String {
        let trimmed = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Project" : trimmed
    }

    private var resolvedContextMode: ProjectContextMode {
        ProjectContextMode(rawValue: project.contextMode) ?? .directInjection
    }

    private var sortedDocuments: [ProjectDocumentEntity] {
        project.documents.sorted { $0.addedAt > $1.addedAt }
    }

    private var readyDocumentCount: Int {
        project.documents.filter { $0.processingStatus == "ready" }.count
    }

    private var totalTokenEstimate: Int {
        project.documents
            .compactMap(\.extractedText)
            .reduce(0) { $0 + Int(ceil(Double($1.count) / 3.5)) }
    }

    private var formattedTokenCount: String {
        if totalTokenEstimate >= 1000 {
            return "\(totalTokenEstimate / 1000)K"
        }
        return "\(totalTokenEstimate)"
    }

    private var enabledEmbeddingProviders: [EmbeddingProviderConfigEntity] {
        embeddingProviders.filter(\.isEnabled)
    }

    private var enabledRerankProviders: [RerankProviderConfigEntity] {
        rerankProviders.filter(\.isEnabled)
    }

    private var supportedContentTypes: [UTType] {
        [.pdf, .plainText, .json, .commaSeparatedText, .html, .xml, .yaml, .sourceCode]
    }

    @ViewBuilder
    private var projectIcon: some View {
        let trimmed = (project.icon ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        Group {
            if trimmed.isEmpty {
                Image(systemName: "folder.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else if trimmed.count <= 2 {
                Text(trimmed)
                    .font(.system(size: 24))
            } else {
                Image(systemName: trimmed)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    // MARK: - Bindings

    private var nameBinding: Binding<String> {
        Binding(
            get: { project.name },
            set: { newValue in
                project.name = newValue
                project.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var iconBinding: Binding<String> {
        Binding(
            get: { project.icon ?? "" },
            set: { newValue in
                project.icon = newValue.isEmpty ? nil : newValue
                project.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var descriptionBinding: Binding<String> {
        Binding(
            get: { project.projectDescription ?? "" },
            set: { newValue in
                project.projectDescription = newValue.isEmpty ? nil : newValue
                project.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var customInstructionBinding: Binding<String> {
        Binding(
            get: { project.customInstruction ?? "" },
            set: { newValue in
                project.customInstruction = newValue.isEmpty ? nil : newValue
                project.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var contextModeBinding: Binding<ProjectContextMode> {
        Binding(
            get: { resolvedContextMode },
            set: { newValue in
                project.contextMode = newValue.rawValue
                project.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var embeddingProviderIDBinding: Binding<String?> {
        Binding(
            get: { project.embeddingProviderID },
            set: { newValue in
                project.embeddingProviderID = newValue
                project.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var embeddingModelIDBinding: Binding<String?> {
        Binding(
            get: { project.embeddingModelID },
            set: { newValue in
                project.embeddingModelID = newValue
                project.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var rerankProviderIDBinding: Binding<String?> {
        Binding(
            get: { project.rerankProviderID },
            set: { newValue in
                project.rerankProviderID = newValue
                project.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var rerankModelIDBinding: Binding<String?> {
        Binding(
            get: { project.rerankModelID },
            set: { newValue in
                project.rerankModelID = newValue
                project.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    // MARK: - Actions

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                addDocument(from: url)
            }
        case .failure(let error):
            documentError = error.localizedDescription
            showingDocumentError = true
        }
    }

    private func addDocument(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            documentError = "Cannot access file: \(url.lastPathComponent)"
            showingDocumentError = true
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        isProcessingDocument = true

        Task {
            do {
                let storageManager = try ProjectDocumentStorageManager()
                let filename = url.lastPathComponent
                let ext = url.pathExtension.lowercased()
                let mimeType = ProjectDocumentTextExtractor.mimeType(for: ext)

                let stored = try await storageManager.saveDocument(
                    from: url,
                    filename: filename,
                    mimeType: mimeType,
                    projectID: project.id
                )

                let documentEntity = ProjectDocumentEntity(
                    id: stored.id,
                    filename: stored.filename,
                    mimeType: stored.mimeType,
                    fileURL: stored.fileURL,
                    fileSizeBytes: stored.fileSizeBytes,
                    processingStatus: "extracting"
                )

                await MainActor.run {
                    documentEntity.project = project
                    project.documents.append(documentEntity)
                    modelContext.insert(documentEntity)
                    try? modelContext.save()
                }

                // Extract text
                let extractedText = ProjectDocumentTextExtractor.extractText(from: stored.fileURL)

                await MainActor.run {
                    documentEntity.extractedText = extractedText
                    documentEntity.processingStatus = extractedText != nil ? "ready" : "failed"
                    if extractedText == nil {
                        documentEntity.processingError = "Could not extract text from this file."
                    }
                    project.updatedAt = Date()
                    try? modelContext.save()
                    isProcessingDocument = false
                }
            } catch {
                await MainActor.run {
                    documentError = "Failed to add document: \(error.localizedDescription)"
                    showingDocumentError = true
                    isProcessingDocument = false
                }
            }
        }
    }

    private func deleteDocument(_ document: ProjectDocumentEntity) {
        Task {
            do {
                let storageManager = try ProjectDocumentStorageManager()
                try await storageManager.deleteDocument(at: document.fileURL)
            } catch {
                // File deletion failure is non-fatal; proceed with entity removal
            }

            await MainActor.run {
                modelContext.delete(document)
                project.updatedAt = Date()
                try? modelContext.save()
                documentPendingDeletion = nil
            }
        }
    }
}
