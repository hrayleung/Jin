import Alamofire

/// Extracts the underlying error from an `AFError` when it represents a transport-level
/// failure (task failed, session invalidated/deinitialized, or explicit cancellation).
/// Returns `nil` for non-transport errors (serialization, validation) which are safe to
/// ignore since we handle HTTP status codes and raw data ourselves.
///
/// Shared between `NetworkManager` and `NetworkDebugRequestExecutor` to keep
/// cancellation / transport mapping in sync.
func extractAlamofireTransportError(from afError: AFError?) -> Error? {
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
            return extractAlamofireTransportError(from: afOriginal)
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
