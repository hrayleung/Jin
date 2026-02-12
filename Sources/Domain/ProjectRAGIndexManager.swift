import Foundation
import SwiftData

/// Manages RAG indexing and retrieval for project documents.
actor ProjectRAGIndexManager {
    /// Index a document: chunk text, embed chunks, store vectors.
    func indexDocument(
        _ document: ProjectDocumentEntity,
        embeddingAdapter: any EmbeddingProviderAdapter,
        embeddingModelID: String,
        modelContext: ModelContext
    ) async throws {
        guard let text = document.extractedText, !text.isEmpty else {
            throw RAGError.noTextToIndex
        }

        // Chunk the document
        let chunks = DocumentChunker.chunk(
            text: text,
            sourceFilename: document.filename
        )

        guard !chunks.isEmpty else {
            throw RAGError.noChunksProduced
        }

        // Embed in batches (most APIs limit batch size)
        let batchSize = 64
        var allEmbeddings: [[Float]] = []

        for batchStart in stride(from: 0, to: chunks.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, chunks.count)
            let batchTexts = chunks[batchStart..<batchEnd].map(\.text)

            let response = try await embeddingAdapter.embed(
                texts: batchTexts,
                modelID: embeddingModelID,
                inputType: .searchDocument
            )

            allEmbeddings.append(contentsOf: response.embeddings)
        }

        guard allEmbeddings.count == chunks.count else {
            throw RAGError.embeddingCountMismatch
        }

        // Remove existing chunks for this document
        await removeDocumentIndex(document.id, modelContext: modelContext)

        // Store new chunks with embeddings
        await MainActor.run {
            for (chunk, embedding) in zip(chunks, allEmbeddings) {
                let embeddingData = embedding.withUnsafeBufferPointer { buffer in
                    Data(buffer: buffer)
                }

                let chunkEntity = DocumentChunkEntity(
                    chunkIndex: chunk.index,
                    text: chunk.text,
                    embeddingData: embeddingData,
                    startOffset: chunk.startOffset,
                    endOffset: chunk.endOffset
                )
                chunkEntity.document = document
                document.chunks.append(chunkEntity)
                modelContext.insert(chunkEntity)
            }

            document.chunkCount = chunks.count
            document.processingStatus = "ready"
            try? modelContext.save()
        }
    }

    /// Remove a document's index (all chunks).
    func removeDocumentIndex(_ documentID: UUID, modelContext: ModelContext) async {
        await MainActor.run {
            let descriptor = FetchDescriptor<DocumentChunkEntity>(
                predicate: #Predicate { $0.document?.id == documentID }
            )

            if let existingChunks = try? modelContext.fetch(descriptor) {
                for chunk in existingChunks {
                    modelContext.delete(chunk)
                }
            }
            try? modelContext.save()
        }
    }

    /// Retrieve relevant chunks for a query using cosine similarity.
    func retrieve(
        query: String,
        project: ProjectEntity,
        embeddingAdapter: any EmbeddingProviderAdapter,
        embeddingModelID: String,
        rerankAdapter: (any RerankProviderAdapter)?,
        rerankModelID: String?,
        topK: Int = 10,
        modelContext: ModelContext
    ) async throws -> [RetrievedChunk] {
        // Embed the query
        let queryResponse = try await embeddingAdapter.embed(
            texts: [query],
            modelID: embeddingModelID,
            inputType: .searchQuery
        )

        guard let queryEmbedding = queryResponse.embeddings.first else {
            throw RAGError.queryEmbeddingFailed
        }

        // Load all chunk embeddings for project
        let allChunks = await loadProjectChunks(project: project, modelContext: modelContext)
        guard !allChunks.isEmpty else { return [] }

        // Cosine similarity search
        let overRetrieveK = rerankAdapter != nil ? topK * 3 : topK
        let candidates = cosineSimilaritySearch(
            queryEmbedding: queryEmbedding,
            chunks: allChunks,
            topK: overRetrieveK
        )

        // Optional reranking
        if let rerankAdapter, let rerankModelID {
            let documentTexts = candidates.map(\.text)
            let rerankResponse = try await rerankAdapter.rerank(
                query: query,
                documents: documentTexts,
                modelID: rerankModelID,
                topN: topK
            )

            return rerankResponse.results.prefix(topK).map { result in
                let candidate = candidates[result.index]
                return RetrievedChunk(
                    documentFilename: candidate.filename,
                    text: candidate.text,
                    relevanceScore: result.relevanceScore,
                    chunkIndex: candidate.chunkIndex
                )
            }
        }

        // Return top-K from vector search
        return candidates.prefix(topK).map { candidate in
            RetrievedChunk(
                documentFilename: candidate.filename,
                text: candidate.text,
                relevanceScore: Double(candidate.score),
                chunkIndex: candidate.chunkIndex
            )
        }
    }

    // MARK: - Private

    private struct ChunkWithEmbedding {
        let text: String
        let filename: String
        let chunkIndex: Int
        let embedding: [Float]
        var score: Float = 0
    }

    @MainActor
    private func loadProjectChunks(project: ProjectEntity, modelContext: ModelContext) -> [ChunkWithEmbedding] {
        var result: [ChunkWithEmbedding] = []

        for document in project.documents {
            for chunk in document.chunks {
                guard let embeddingData = chunk.embeddingData else { continue }

                let embedding = embeddingData.withUnsafeBytes { buffer -> [Float] in
                    guard let pointer = buffer.baseAddress?.assumingMemoryBound(to: Float.self) else {
                        return []
                    }
                    let count = buffer.count / MemoryLayout<Float>.size
                    return Array(UnsafeBufferPointer(start: pointer, count: count))
                }

                guard !embedding.isEmpty else { continue }

                result.append(ChunkWithEmbedding(
                    text: chunk.text,
                    filename: document.filename,
                    chunkIndex: chunk.chunkIndex,
                    embedding: embedding
                ))
            }
        }

        return result
    }

    private func cosineSimilaritySearch(
        queryEmbedding: [Float],
        chunks: [ChunkWithEmbedding],
        topK: Int
    ) -> [ChunkWithEmbedding] {
        let queryMagnitude = sqrt(queryEmbedding.reduce(0) { $0 + $1 * $1 })
        guard queryMagnitude > 0 else { return [] }

        var scored = chunks.map { chunk -> ChunkWithEmbedding in
            var result = chunk
            let dotProduct = zip(queryEmbedding, chunk.embedding).reduce(Float(0)) { $0 + $1.0 * $1.1 }
            let chunkMagnitude = sqrt(chunk.embedding.reduce(Float(0)) { $0 + $1 * $1 })

            if chunkMagnitude > 0 {
                result.score = dotProduct / (queryMagnitude * chunkMagnitude)
            }
            return result
        }

        scored.sort { $0.score > $1.score }
        return Array(scored.prefix(topK))
    }
}

/// RAG-specific errors.
enum RAGError: Error, LocalizedError {
    case noTextToIndex
    case noChunksProduced
    case embeddingCountMismatch
    case queryEmbeddingFailed
    case noEmbeddingProvider

    var errorDescription: String? {
        switch self {
        case .noTextToIndex:
            return "Document has no extracted text to index."
        case .noChunksProduced:
            return "Document text could not be chunked."
        case .embeddingCountMismatch:
            return "Number of embeddings does not match number of chunks."
        case .queryEmbeddingFailed:
            return "Failed to generate query embedding."
        case .noEmbeddingProvider:
            return "No embedding provider configured."
        }
    }
}
