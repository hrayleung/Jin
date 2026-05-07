import Foundation

struct CloudflareR2Configuration: Equatable {
    let accountID: String
    let accessKeyID: String
    let secretAccessKey: String
    let bucket: String
    let publicBaseURL: String
    let keyPrefix: String

    init(
        accountID: String,
        accessKeyID: String,
        secretAccessKey: String,
        bucket: String,
        publicBaseURL: String,
        keyPrefix: String
    ) {
        self.accountID = accountID.trimmed
        self.accessKeyID = accessKeyID.trimmed
        self.secretAccessKey = secretAccessKey.trimmed
        self.bucket = bucket.trimmed
        self.publicBaseURL = publicBaseURL.trimmed
        self.keyPrefix = keyPrefix.trimmed
    }

    static func load(from defaults: UserDefaults = .standard) -> CloudflareR2Configuration {
        CloudflareR2Configuration(
            accountID: defaults.string(forKey: AppPreferenceKeys.cloudflareR2AccountID) ?? "",
            accessKeyID: defaults.string(forKey: AppPreferenceKeys.cloudflareR2AccessKeyID) ?? "",
            secretAccessKey: defaults.string(forKey: AppPreferenceKeys.cloudflareR2SecretAccessKey) ?? "",
            bucket: defaults.string(forKey: AppPreferenceKeys.cloudflareR2Bucket) ?? "",
            publicBaseURL: defaults.string(forKey: AppPreferenceKeys.cloudflareR2PublicBaseURL) ?? "",
            keyPrefix: defaults.string(forKey: AppPreferenceKeys.cloudflareR2KeyPrefix) ?? ""
        )
    }

    var missingRequiredFields: [String] {
        var out: [String] = []
        if accountID.isEmpty { out.append("Account ID") }
        if accessKeyID.isEmpty { out.append("Access Key ID") }
        if secretAccessKey.isEmpty { out.append("Secret Access Key") }
        if bucket.isEmpty { out.append("Bucket") }
        if publicBaseURL.isEmpty { out.append("Public Base URL") }
        return out
    }

    var normalizedKeyPrefix: String? {
        let trimmed = keyPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? nil : trimmed
    }

    var uploadHost: String {
        "\(accountID).r2.cloudflarestorage.com"
    }

    func validated() throws -> CloudflareR2Configuration {
        let missing = missingRequiredFields
        guard missing.isEmpty else {
            throw CloudflareR2UploaderError.missingConfiguration(fields: missing)
        }

        guard var components = URLComponents(string: publicBaseURL),
              let scheme = components.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              components.host?.isEmpty == false,
              components.query?.isEmpty ?? true,
              components.fragment?.isEmpty ?? true else {
            throw CloudflareR2UploaderError.invalidPublicBaseURL(publicBaseURL)
        }

        let normalizedPath = components.percentEncodedPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = normalizedPath.isEmpty ? "" : "/\(normalizedPath)"

        guard components.url != nil else {
            throw CloudflareR2UploaderError.invalidPublicBaseURL(publicBaseURL)
        }
        return self
    }

    func publicURL(for objectKey: String) throws -> URL {
        guard var components = URLComponents(string: publicBaseURL),
              let scheme = components.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              components.host?.isEmpty == false else {
            throw CloudflareR2UploaderError.invalidPublicBaseURL(publicBaseURL)
        }

        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encodedKey = objectKey
            .split(separator: "/")
            .map { R2Signing.percentEncodePathSegment(String($0)) }
            .joined(separator: "/")

        if basePath.isEmpty {
            components.percentEncodedPath = "/\(encodedKey)"
        } else {
            components.percentEncodedPath = "/\(basePath)/\(encodedKey)"
        }
        components.query = nil
        components.fragment = nil

        guard let url = components.url else {
            throw CloudflareR2UploaderError.invalidPublicBaseURL(publicBaseURL)
        }
        return url
    }

    func objectKey(for publicURL: URL) throws -> String {
        guard let baseComponents = URLComponents(string: publicBaseURL),
              let baseScheme = baseComponents.scheme?.lowercased(),
              let baseHost = baseComponents.host?.lowercased(),
              let publicScheme = publicURL.scheme?.lowercased(),
              let publicHost = publicURL.host?.lowercased(),
              baseScheme == publicScheme,
              baseHost == publicHost else {
            throw CloudflareR2UploaderError.publicURLValidationFailed(
                message: "Uploaded object URL does not match the configured Cloudflare R2 public base URL."
            )
        }

        let basePath = baseComponents.percentEncodedPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let publicPath = (URLComponents(url: publicURL, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? publicURL.path)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let expectedPrefix = basePath.isEmpty ? "" : "\(basePath)/"

        let encodedKey: String
        if basePath.isEmpty {
            encodedKey = publicPath
        } else if publicPath.hasPrefix(expectedPrefix) {
            encodedKey = String(publicPath.dropFirst(expectedPrefix.count))
        } else {
            throw CloudflareR2UploaderError.publicURLValidationFailed(
                message: "Uploaded object URL does not live under the configured Cloudflare R2 public base path."
            )
        }

        guard !encodedKey.isEmpty else {
            throw CloudflareR2UploaderError.publicURLValidationFailed(
                message: "Uploaded object URL did not contain an object key."
            )
        }

        return encodedKey
            .split(separator: "/")
            .map { $0.removingPercentEncoding ?? String($0) }
            .joined(separator: "/")
    }
}
