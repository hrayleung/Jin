import Foundation

/// Shared helper for one-shot URLSession requests outside `NetworkManager`.
/// It intentionally skips trace logging to avoid noisy non-LLM network traffic.
enum NetworkDebugRequestExecutor {
    static func data(
        for request: URLRequest,
        mode: String,
        session: URLSession? = nil
    ) async throws -> (Data, URLResponse) {
        _ = mode
        let resolvedSession = session ?? .shared
        return try await resolvedSession.data(for: request)
    }
}
