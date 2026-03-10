import Foundation
import Alamofire

/// Shared helper for one-shot requests outside `NetworkManager`.
/// It intentionally skips trace logging to avoid noisy non-LLM network traffic.
enum NetworkDebugRequestExecutor {
    private static let defaultSession: Session = {
        let configuration = NetworkManager.makeDefaultSessionConfiguration()
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

    static func data(
        for request: URLRequest,
        mode: String,
        alamofireSession: Session? = nil
    ) async throws -> (Data, URLResponse) {
        _ = mode

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
