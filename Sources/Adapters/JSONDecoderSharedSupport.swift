import Foundation

extension JSONDecoder {
    /// Shared decoder configured only with `.convertFromSnakeCase`. Mirrors the
    /// per-module cached decoders that already existed; safe to share because
    /// JSONDecoder is used read-only for decoding.
    static let snakeCaseConverting: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// Decodes `T`, or throws `LLMError.decodingError` carrying the raw response
    /// body (falling back to the underlying error description) on failure.
    func decodeOrThrowRawBody<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try decode(type, from: data) }
        catch {
            let message = String(data: data, encoding: .utf8) ?? error.localizedDescription
            throw LLMError.decodingError(message: message)
        }
    }
}
