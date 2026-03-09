import Foundation
import Alamofire

/// Shared helper for one-shot URLSession requests outside `NetworkManager`.
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
        session: URLSession? = nil,
        alamofireSession: Session? = nil
    ) async throws -> (Data, URLResponse) {
        _ = mode
        if let session {
            return try await session.data(for: request)
        }

        let response = await (alamofireSession ?? defaultSession)
            .request(request)
            .serializingData(automaticallyCancelling: true)
            .response

        if let transportError = extractTransportError(from: response.error) {
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

    private static func extractTransportError(from afError: AFError?) -> Error? {
        guard let afError else { return nil }

        switch afError {
        case .sessionTaskFailed(let error):
            return error
        case .sessionInvalidated(let error):
            return error ?? afError
        case .sessionDeinitialized:
            return afError
        case .explicitlyCancelled:
            return afError
        case .requestRetryFailed(_, let originalError):
            if let afOriginal = originalError as? AFError {
                return extractTransportError(from: afOriginal)
            }
            return originalError
        case .createURLRequestFailed,
             .invalidURL,
             .multipartEncodingFailed,
             .parameterEncodingFailed,
             .parameterEncoderFailed,
             .requestAdaptationFailed,
             .responseSerializationFailed,
             .responseValidationFailed,
             .urlRequestValidationFailed:
            return nil
        #if canImport(Security)
        case .serverTrustEvaluationFailed:
            return afError
        #endif
        case .createUploadableFailed,
             .downloadedFileMoveFailed:
            return nil
        @unknown default:
            return nil
        }
    }
}
