import Foundation

/// Builds project context for injection into the system prompt.
enum ProjectContextInjector {
    struct InjectionResult {
        let contextText: String
        let approximateTokenCount: Int
        let modeUsed: ProjectContextMode
        let documentsIncluded: Int
        let documentsOmitted: Int
    }

    /// Minimum tokens reserved for conversation history.
    private static let minConversationHistoryTokens = 8_000

    /// Approximate characters per token (conservative estimate).
    private static let charsPerToken: Double = 3.5

    /// Build context from project documents for injection into the system prompt.
    ///
    /// - Parameters:
    ///   - documents: The project's documents with extracted text.
    ///   - customInstruction: Optional project-specific system prompt addition.
    ///   - query: The user's latest message (used for RAG retrieval in Phase 2).
    ///   - contextMode: Whether to use direct injection or RAG.
    ///   - modelContextWindow: The model's total context window in tokens.
    ///   - reservedTokens: Tokens reserved for system prompt + output.
    ///   - retrievedChunks: Pre-retrieved RAG chunks (Phase 2).
    /// - Returns: The injection result containing formatted context text.
    static func buildContext(
        documents: [ProjectDocumentEntity],
        customInstruction: String?,
        query: String?,
        contextMode: ProjectContextMode,
        modelContextWindow: Int,
        reservedTokens: Int,
        retrievedChunks: [RetrievedChunk]? = nil
    ) -> InjectionResult {
        let availableTokens = modelContextWindow - reservedTokens - minConversationHistoryTokens
        let maxCharacters = Int(Double(max(0, availableTokens)) * charsPerToken)

        var parts: [String] = []

        // Add custom instruction if present
        if let instruction = customInstruction?.trimmingCharacters(in: .whitespacesAndNewlines),
           !instruction.isEmpty {
            parts.append(instruction)
        }

        switch contextMode {
        case .directInjection:
            let result = buildDirectInjectionContext(
                documents: documents,
                maxCharacters: maxCharacters
            )
            if !result.text.isEmpty {
                parts.append(result.text)
            }

            let fullText = parts.joined(separator: "\n\n")
            let tokenEstimate = estimateTokenCount(fullText)

            return InjectionResult(
                contextText: fullText,
                approximateTokenCount: tokenEstimate,
                modeUsed: .directInjection,
                documentsIncluded: result.included,
                documentsOmitted: result.omitted
            )

        case .rag:
            if let chunks = retrievedChunks, !chunks.isEmpty {
                let ragText = buildRAGContext(chunks: chunks, maxCharacters: maxCharacters)
                if !ragText.isEmpty {
                    parts.append(ragText)
                }

                let fullText = parts.joined(separator: "\n\n")
                let tokenEstimate = estimateTokenCount(fullText)

                return InjectionResult(
                    contextText: fullText,
                    approximateTokenCount: tokenEstimate,
                    modeUsed: .rag,
                    documentsIncluded: Set(chunks.map(\.documentFilename)).count,
                    documentsOmitted: 0
                )
            }

            // Fallback to direct injection if no chunks available
            let result = buildDirectInjectionContext(
                documents: documents,
                maxCharacters: maxCharacters
            )
            if !result.text.isEmpty {
                parts.append(result.text)
            }

            let fullText = parts.joined(separator: "\n\n")
            let tokenEstimate = estimateTokenCount(fullText)

            return InjectionResult(
                contextText: fullText,
                approximateTokenCount: tokenEstimate,
                modeUsed: .directInjection,
                documentsIncluded: result.included,
                documentsOmitted: result.omitted
            )
        }
    }

    // MARK: - Direct Injection

    private struct DirectInjectionResult {
        let text: String
        let included: Int
        let omitted: Int
    }

    private static func buildDirectInjectionContext(
        documents: [ProjectDocumentEntity],
        maxCharacters: Int
    ) -> DirectInjectionResult {
        let readyDocuments = documents
            .filter { $0.processingStatus == "ready" && $0.extractedText != nil }
            .sorted { $0.addedAt > $1.addedAt } // Most recent first

        guard !readyDocuments.isEmpty else {
            return DirectInjectionResult(text: "", included: 0, omitted: 0)
        }

        var sections: [String] = []
        var totalCharacters = 0
        var included = 0
        let headerFooterOverhead = 120 // Approximate overhead for wrapper tags

        for document in readyDocuments {
            guard let text = document.extractedText else { continue }

            let section = "--- \(document.filename) ---\n\(text)"
            let sectionLength = section.count

            if totalCharacters + sectionLength + headerFooterOverhead > maxCharacters {
                break
            }

            sections.append(section)
            totalCharacters += sectionLength
            included += 1
        }

        let omitted = readyDocuments.count - included

        guard !sections.isEmpty else {
            return DirectInjectionResult(text: "", included: 0, omitted: readyDocuments.count)
        }

        var result = "<project_knowledge>\nThe following documents are part of this project's knowledge base.\n\n"
        result += sections.joined(separator: "\n\n")

        if omitted > 0 {
            result += "\n\n[Note: \(omitted) document(s) omitted due to context window limits.]"
        }

        result += "\n</project_knowledge>"

        return DirectInjectionResult(text: result, included: included, omitted: omitted)
    }

    // MARK: - RAG Context

    private static func buildRAGContext(chunks: [RetrievedChunk], maxCharacters: Int) -> String {
        guard !chunks.isEmpty else { return "" }

        var sections: [String] = []
        var totalCharacters = 0
        let headerFooterOverhead = 150

        for chunk in chunks {
            let scoreStr = String(format: "%.2f", chunk.relevanceScore)
            let section = "--- From: \(chunk.documentFilename) (relevance: \(scoreStr)) ---\n\(chunk.text)"
            let sectionLength = section.count

            if totalCharacters + sectionLength + headerFooterOverhead > maxCharacters {
                break
            }

            sections.append(section)
            totalCharacters += sectionLength
        }

        guard !sections.isEmpty else { return "" }

        var result = "<project_knowledge>\nThe following excerpts from project documents are relevant to your question.\n\n"
        result += sections.joined(separator: "\n\n")
        result += "\n</project_knowledge>"

        return result
    }

    // MARK: - Token Estimation

    private static func estimateTokenCount(_ text: String) -> Int {
        Int(ceil(Double(text.count) / charsPerToken))
    }
}

/// Represents a retrieved chunk from RAG search.
struct RetrievedChunk {
    let documentFilename: String
    let text: String
    let relevanceScore: Double
    let chunkIndex: Int
}
