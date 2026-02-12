import Foundation

/// Splits text into overlapping chunks for RAG indexing.
enum DocumentChunker {
    struct Chunk {
        let text: String
        let startOffset: Int
        let endOffset: Int
        let index: Int
    }

    /// Default chunk size in characters (~512 tokens at ~4 chars/token).
    static let defaultChunkSize = 2000

    /// Default overlap in characters (~64 tokens).
    static let defaultOverlapSize = 256

    /// Split text into overlapping chunks, breaking on paragraph boundaries.
    ///
    /// - Parameters:
    ///   - text: The full document text.
    ///   - chunkSize: Target size per chunk in characters.
    ///   - overlapSize: Overlap between consecutive chunks in characters.
    ///   - sourceFilename: Optional filename prepended to each chunk as metadata.
    /// - Returns: Array of chunks with positional information.
    static func chunk(
        text: String,
        chunkSize: Int = defaultChunkSize,
        overlapSize: Int = defaultOverlapSize,
        sourceFilename: String? = nil
    ) -> [Chunk] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let paragraphs = splitIntoParagraphs(trimmed)
        var chunks: [Chunk] = []
        var currentSegments: [String] = []
        var currentLength = 0
        var chunkStartOffset = 0
        var runningOffset = 0

        for paragraph in paragraphs {
            let paragraphLength = paragraph.count

            // If adding this paragraph exceeds chunk size and we have content, finalize chunk
            if currentLength + paragraphLength > chunkSize && !currentSegments.isEmpty {
                let chunkText = buildChunkText(
                    segments: currentSegments,
                    sourceFilename: sourceFilename
                )
                let endOffset = runningOffset

                chunks.append(Chunk(
                    text: chunkText,
                    startOffset: chunkStartOffset,
                    endOffset: endOffset,
                    index: chunks.count
                ))

                // Calculate overlap: keep trailing segments that fit within overlap
                var overlapSegments: [String] = []
                var overlapLength = 0
                for segment in currentSegments.reversed() {
                    if overlapLength + segment.count > overlapSize {
                        break
                    }
                    overlapSegments.insert(segment, at: 0)
                    overlapLength += segment.count
                }

                currentSegments = overlapSegments
                currentLength = overlapLength
                chunkStartOffset = endOffset - overlapLength
            }

            currentSegments.append(paragraph)
            currentLength += paragraphLength
            runningOffset += paragraphLength
        }

        // Final chunk
        if !currentSegments.isEmpty {
            let chunkText = buildChunkText(
                segments: currentSegments,
                sourceFilename: sourceFilename
            )
            chunks.append(Chunk(
                text: chunkText,
                startOffset: chunkStartOffset,
                endOffset: runningOffset,
                index: chunks.count
            ))
        }

        return chunks
    }

    // MARK: - Private

    private static func splitIntoParagraphs(_ text: String) -> [String] {
        let rawParagraphs = text.components(separatedBy: "\n\n")
        return rawParagraphs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func buildChunkText(segments: [String], sourceFilename: String?) -> String {
        var result = ""
        if let filename = sourceFilename {
            result = "[Source: \(filename)]\n"
        }
        result += segments.joined(separator: "\n\n")
        return result
    }
}
