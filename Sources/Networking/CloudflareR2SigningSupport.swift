import Foundation
import CryptoKit

enum CloudflareR2SignedRequestFactory {
    static func makeRequest(
        method: String,
        configuration: CloudflareR2Configuration,
        objectKey: String,
        payloadData: Data,
        contentType: String?,
        date: Date = Date()
    ) throws -> URLRequest {
        let normalizedMethod = method.uppercased()
        let amzDate = CloudflareR2DateFormatter.amzDateString(from: date)
        let dateStamp = String(amzDate.prefix(8))
        let credentialScope = "\(dateStamp)/auto/s3/aws4_request"

        let canonicalURI = R2Signing.canonicalURI(bucket: configuration.bucket, objectKey: objectKey)
        let canonicalQuery = ""
        let payloadHash = R2Signing.sha256Hex(payloadData)

        var headers: [String: String] = [
            "host": configuration.uploadHost,
            "x-amz-content-sha256": payloadHash,
            "x-amz-date": amzDate
        ]
        if let contentType, !contentType.isEmpty {
            headers["content-type"] = contentType
        }

        let canonicalHeaders = Self.canonicalHeaders(from: headers)
        let signedHeaders = Self.signedHeaders(from: headers)
        let canonicalRequest = [
            normalizedMethod,
            canonicalURI,
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            R2Signing.sha256Hex(Data(canonicalRequest.utf8))
        ].joined(separator: "\n")

        let signingKey = R2Signing.signingKey(
            secretAccessKey: configuration.secretAccessKey,
            dateStamp: dateStamp,
            region: "auto",
            service: "s3"
        )
        let signature = R2Signing.hmacHex(key: signingKey, message: stringToSign)
        let authorization = "AWS4-HMAC-SHA256 Credential=\(configuration.accessKeyID)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        var components = URLComponents()
        components.scheme = "https"
        components.host = configuration.uploadHost
        components.percentEncodedPath = canonicalURI

        guard let url = components.url else {
            throw LLMError.invalidRequest(message: "Failed to build Cloudflare R2 request URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = normalizedMethod
        request.httpBody = payloadData.isEmpty ? nil : payloadData
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        return request
    }

    private static func canonicalHeaders(from headers: [String: String]) -> String {
        headers.keys.sorted()
            .map { "\($0):\(headers[$0]!.trimmed)\n" }
            .joined()
    }

    private static func signedHeaders(from headers: [String: String]) -> String {
        headers.keys.sorted().joined(separator: ";")
    }
}

enum CloudflareR2DateFormatter {
    static func amzDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    static func dayStamp(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }
}

enum R2Signing {
    static func canonicalURI(bucket: String, objectKey: String) -> String {
        var segments = [bucket]
        segments.append(contentsOf: objectKey.split(separator: "/").map(String.init))
        let encoded = segments.map(percentEncodePathSegment).joined(separator: "/")
        return "/\(encoded)"
    }

    static func percentEncodePathSegment(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: unreservedCharacters) ?? segment
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256HexDigest.data(data)
    }

    static func hmacHex(key: Data, message: String) -> String {
        hmacData(key: key, message: message).map { String(format: "%02x", $0) }.joined()
    }

    static func signingKey(secretAccessKey: String, dateStamp: String, region: String, service: String) -> Data {
        let secret = Data(("AWS4" + secretAccessKey).utf8)
        let kDate = hmacData(key: secret, message: dateStamp)
        let kRegion = hmacData(key: kDate, message: region)
        let kService = hmacData(key: kRegion, message: service)
        return hmacData(key: kService, message: "aws4_request")
    }

    private static func hmacData(key: Data, message: String) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let code = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: symmetricKey)
        return Data(code)
    }

    private static let unreservedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
