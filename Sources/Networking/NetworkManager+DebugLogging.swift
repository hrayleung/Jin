import Foundation

extension NetworkManager {
    private nonisolated static var debugLogBodySummaryLabel: String {
        "response body omitted from network trace"
    }

    nonisolated static func makeDebugLogResponseBody(
        _ responseBody: Data?,
        response: HTTPURLResponse?,
        wasTruncated: Bool
    ) -> Data? {
        guard let responseBody, !responseBody.isEmpty else { return nil }

        var summary = "\(debugLogBodySummaryLabel) (\(responseBody.count) bytes"
        if let contentType = response?.value(forHTTPHeaderField: "Content-Type")?
            .trimmed,
           !contentType.isEmpty {
            summary += ", content-type: \(contentType)"
        }
        if wasTruncated {
            summary += ", truncated while capturing"
        }
        summary += ")"
        return Data(summary.utf8)
    }
}
