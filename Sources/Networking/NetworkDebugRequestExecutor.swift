import Foundation
import Alamofire

/// Closure that fetches raw HTTP data for a request, used to decouple
/// UI/Persistence layers from Alamofire. Matches `URLSession.data(for:)`.
typealias HTTPDataProvider = @Sendable (URLRequest) async throws -> (Data, URLResponse)

/// Shared helper for one-shot requests outside `NetworkManager`.
/// It intentionally skips trace logging to avoid noisy non-LLM network traffic.
enum NetworkDebugRequestExecutor {
    private static let defaultSession: Session = {
        let configuration = makeDefaultSessionConfiguration()
        let rootQueue = DispatchQueue(label: "jin.network.utility.alamofire.root")
        let requestQueue = DispatchQueue(label: "jin.network.utility.alamofire.request", target: rootQueue)
        let serializationQueue = DispatchQueue(label: "jin.network.utility.alamofire.serialization", target: rootQueue)

        return Session(
            configuration: configuration,
            rootQueue: rootQueue,
            requestSetup: .lazy,
            requestQueue: requestQueue,
            serializationQueue: serializationQueue
        )
    }()

    nonisolated static func makeDefaultSessionConfiguration() -> URLSessionConfiguration {
        let sharedConfiguration = URLSession.shared.configuration
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = sharedConfiguration.timeoutIntervalForRequest
        configuration.timeoutIntervalForResource = sharedConfiguration.timeoutIntervalForResource
        return configuration
    }

    /// Execute a one-shot data request.
    ///
    /// - Parameters:
    ///   - dataProvider: Optional closure that bypasses the internal Alamofire session.
    ///     Allows UI/Persistence callers (and their tests) to inject a plain `URLSession`
    ///     without importing Alamofire.
    ///   - alamofireSession: Optional Alamofire session override for Networking-layer tests
    ///     that verify Alamofire-specific behavior (transport error extraction, etc.).
    ///     Ignored when `dataProvider` is set.
    static func data(
        for request: URLRequest,
        mode: String,
        dataProvider: HTTPDataProvider? = nil,
        alamofireSession: Session? = nil
    ) async throws -> (Data, URLResponse) {
        _ = mode

        if let dataProvider {
            return try await dataProvider(request)
        }

        let response = await (alamofireSession ?? defaultSession)
            .request(request)
            .serializingData(automaticallyCancelling: true)
            .response

        if let transportError = extractAlamofireTransportError(from: response.error) {
            throw transportError
        }

        if let error = response.error {
            throw error.underlyingError ?? error
        }

        guard let httpResponse = response.response else {
            throw URLError(.badServerResponse)
        }

        return (response.data ?? Data(), httpResponse)
    }
}
