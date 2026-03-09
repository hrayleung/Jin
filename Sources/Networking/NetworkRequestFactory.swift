import Foundation
import Alamofire

enum NetworkRequestFactory {
    static func makeRequest(
        url: URL,
        method: String = "GET",
        timeoutSeconds: TimeInterval? = nil,
        headers: [String: String] = [:],
        body: Data? = nil
    ) -> URLRequest {
        makeRequest(
            url: url,
            method: resolvedHTTPMethod(method),
            timeoutSeconds: timeoutSeconds,
            headers: HTTPHeaders(headers.map { HTTPHeader(name: $0.key, value: $0.value) }),
            body: body
        )
    }

    static func makeRequest(
        url: URL,
        method: HTTPMethod,
        timeoutSeconds: TimeInterval? = nil,
        headers: HTTPHeaders = [],
        body: Data? = nil
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        if let timeoutSeconds {
            request.timeoutInterval = timeoutSeconds
        }

        for header in headers {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }

        request.httpBody = body
        return request
    }

    static func makeJSONRequest<Body: Encodable>(
        url: URL,
        method: HTTPMethod = .post,
        timeoutSeconds: TimeInterval? = nil,
        headers: HTTPHeaders = [],
        body: Body,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> URLRequest {
        var resolvedHeaders = headers
        resolvedHeaders.update(name: "Content-Type", value: "application/json")

        return makeRequest(
            url: url,
            method: method,
            timeoutSeconds: timeoutSeconds,
            headers: resolvedHeaders,
            body: try encoder.encode(body)
        )
    }

    static func makeJSONRequest(
        url: URL,
        method: String = "POST",
        timeoutSeconds: TimeInterval? = nil,
        headers: [String: String] = [:],
        body: [String: Any],
        options: JSONSerialization.WritingOptions = []
    ) throws -> URLRequest {
        var resolvedHeaders = headers
        resolvedHeaders["Content-Type"] = "application/json"

        return makeRequest(
            url: url,
            method: method,
            timeoutSeconds: timeoutSeconds,
            headers: resolvedHeaders,
            body: try JSONSerialization.data(withJSONObject: body, options: options)
        )
    }

    static func makeMultipartRequest(
        url: URL,
        timeoutSeconds: TimeInterval? = nil,
        headers: HTTPHeaders = [],
        buildFormData: (MultipartFormData) -> Void
    ) throws -> URLRequest {
        let formData = MultipartFormData()
        buildFormData(formData)

        var resolvedHeaders = headers
        resolvedHeaders.update(name: "Content-Type", value: formData.contentType)

        return makeRequest(
            url: url,
            method: .post,
            timeoutSeconds: timeoutSeconds,
            headers: resolvedHeaders,
            body: try formData.encode()
        )
    }

    static func bearerHeaders(apiKey: String, additional: HTTPHeaders = []) -> HTTPHeaders {
        var headers = additional
        headers.update(name: "Authorization", value: "Bearer \(apiKey)")
        return headers
    }

    private static func resolvedHTTPMethod(_ method: String) -> HTTPMethod {
        HTTPMethod(rawValue: method.uppercased())
    }
}
