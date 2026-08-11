import Foundation

/// Decodes provider SSE frames into the raw audio chunks the playback layer consumes.
///
/// Every streaming text-to-speech provider Jin supports wraps base64 audio in its own frame
/// shape, so the transport (`NetworkManager.streamRequest`) is shared and only the payload
/// decoding differs.
enum SpeechAudioStreamSupport {

    /// `{"type": "speech.audio.delta", "audio": "<base64>"}` terminated by
    /// `{"type": "speech.audio.done", …}`, with `speech.audio.error` in place of `done` on failure.
    private struct OpenAISpeechEvent: Decodable {
        struct ErrorPayload: Decodable {
            let message: String?
            let code: String?
        }

        let type: String?
        let audio: String?
        let error: ErrorPayload?
    }

    /// `{"choices": [{"delta": {"audio": {"data": "<base64>"}}}]}`
    private struct MiMoStreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                struct Audio: Decodable {
                    let data: String?
                }

                let audio: Audio?
            }

            struct Message: Decodable {
                struct Audio: Decodable {
                    let data: String?
                }

                let audio: Audio?
            }

            let delta: Delta?
            let message: Message?
        }

        let choices: [Choice]?
    }

    static func openAIAudioChunks(
        from events: AsyncThrowingStream<SSEEvent, Error>
    ) -> AsyncThrowingStream<Data, Error> {
        audioChunks(from: events) { payload in
            let event = try JSONDecoder().decode(OpenAISpeechEvent.self, from: payload)

            switch event.type {
            case "speech.audio.error":
                throw LLMError.providerError(
                    code: event.error?.code ?? "speech_audio_error",
                    message: event.error?.message ?? "Speech synthesis failed."
                )
            case "speech.audio.done":
                return nil
            default:
                guard let audio = event.audio?.trimmedNonEmpty else { return nil }
                return Data(base64Encoded: audio)
            }
        }
    }

    static func miMoAudioChunks(
        from events: AsyncThrowingStream<SSEEvent, Error>
    ) -> AsyncThrowingStream<Data, Error> {
        audioChunks(from: events) { payload in
            let chunk = try JSONDecoder().decode(MiMoStreamChunk.self, from: payload)
            let choice = chunk.choices?.first
            guard let audio = (choice?.delta?.audio?.data ?? choice?.message?.audio?.data)?
                .trimmedNonEmpty else {
                return nil
            }
            return Data(base64Encoded: audio)
        }
    }

    /// Bridges an SSE stream into audio chunks, dropping frames the decoder does not recognise.
    ///
    /// A decode failure on a single frame is not fatal — providers interleave usage and
    /// keep-alive frames — but an error the decoder raises deliberately is.
    private static func audioChunks(
        from events: AsyncThrowingStream<SSEEvent, Error>,
        decode: @escaping @Sendable (Data) throws -> Data?
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in events {
                        try Task.checkCancellation()

                        guard case .event(_, let text) = event else { continue }
                        guard let payload = text.data(using: .utf8) else { continue }

                        let audio: Data?
                        do {
                            audio = try decode(payload)
                        } catch let error as LLMError {
                            throw error
                        } catch {
                            continue
                        }

                        if let audio, !audio.isEmpty {
                            continuation.yield(audio)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
