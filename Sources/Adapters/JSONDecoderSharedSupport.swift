import Foundation

extension JSONDecoder {
    /// A freshly-configured `.convertFromSnakeCase` decoder, returned per call.
    /// `JSONDecoder` is not documented as safe to share a single instance across
    /// concurrent decode tasks (and the prior inline code allocated one per decode),
    /// so this is a factory rather than a shared singleton.
    static func snakeCaseConverting() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// Decodes `T`, or throws `LLMError.decodingError` carrying the raw response
    /// body (falling back to the underlying error description) on failure.
    func decodeOrThrowRawBody<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try decode(type, from: data) }
        catch {
            let message = String(data: data, encoding: .utf8) ?? error.localizedDescription
            throw LLMError.decodingError(message: message)
        }
    }

    /// Returns `try? decode(type, from: data)`, or `nil` if `data` is `nil`.
    func decodeOptional<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? decode(type, from: data)
    }
}
