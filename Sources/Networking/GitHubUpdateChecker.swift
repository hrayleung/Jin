import Foundation

struct UpdateVersion: Comparable, Equatable, Sendable {
    let original: String
    private let coreComponents: [Int]
    private let isPrerelease: Bool
    private let prereleaseIdentifiers: [String]

    init?(_ rawVersion: String) {
        var normalized = rawVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        if normalized.hasPrefix("v") || normalized.hasPrefix("V") {
            normalized.removeFirst()
        }
        guard !normalized.hasPrefix("-") else { return nil }

        let versionAndMetadata = normalized.split(separator: "+", omittingEmptySubsequences: true)
        let coreAndPrerelease = versionAndMetadata[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)

        guard let core = coreAndPrerelease.first, !core.isEmpty else {
            return nil
        }
        let prereleaseRaw = coreAndPrerelease.count > 1 ? String(coreAndPrerelease[1]) : nil

        let components = core.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return nil }

        var parsed: [Int] = []
        for component in components {
            guard let value = Int(component) else { return nil }
            parsed.append(value)
        }

        self.original = rawVersion
        self.coreComponents = parsed
        self.isPrerelease = (prereleaseRaw != nil)
        self.prereleaseIdentifiers = prereleaseRaw?.split(separator: ".", omittingEmptySubsequences: false).map(String.init) ?? []
    }

    static func < (lhs: UpdateVersion, rhs: UpdateVersion) -> Bool {
        let maxCount = max(lhs.coreComponents.count, rhs.coreComponents.count)
        for index in 0..<maxCount {
            let left = index < lhs.coreComponents.count ? lhs.coreComponents[index] : 0
            let right = index < rhs.coreComponents.count ? rhs.coreComponents[index] : 0
            if left != right {
                return left < right
            }
        }

        if lhs.isPrerelease != rhs.isPrerelease {
            return lhs.isPrerelease && !rhs.isPrerelease
        }

        guard lhs.isPrerelease,
              rhs.isPrerelease else {
            return false
        }

        return comparePrerelease(lhs.prereleaseIdentifiers, rhs.prereleaseIdentifiers) == .orderedAscending
    }

    private static func comparePrerelease(_ lhs: [String], _ rhs: [String]) -> ComparisonResult {
        let maxCount = max(lhs.count, rhs.count)

        for index in 0..<maxCount {
            if index >= lhs.count {
                return .orderedAscending
            }

            if index >= rhs.count {
                return .orderedDescending
            }

            let lhsIdentifier = lhs[index]
            let rhsIdentifier = rhs[index]

            let lhsNumber = Int(lhsIdentifier)
            let rhsNumber = Int(rhsIdentifier)

            switch (lhsNumber, rhsNumber) {
            case let (.some(left), .some(right)):
                if left != right { return left < right ? .orderedAscending : .orderedDescending }
            case (.some, .none):
                return .orderedAscending
            case (.none, .some):
                return .orderedDescending
            default:
                if lhsIdentifier != rhsIdentifier {
                    return lhsIdentifier.localizedCompare(rhsIdentifier)
                }
            }
        }

        return .orderedSame
    }
}

struct GitHubReleaseCandidate: Sendable {
    struct Asset: Sendable {
        let name: String
        let downloadURL: URL
        let isSourceCodeZip: Bool
    }

    let tagName: String
    let releaseTitle: String
    let body: String
    let htmlURL: URL?
    let publishedAt: Date?
    let asset: Asset
    let currentVersion: String?
    let currentVersionParsed: UpdateVersion?
    let latestVersionParsed: UpdateVersion
    let isUpdateAvailable: Bool
    let isPrerelease: Bool
}

enum GitHubUpdateCheckError: LocalizedError {
    case invalidResponse
    case emptyRelease
    case missingVersion(String)
    case noDownloadableZipAsset
    case repositoryNotFound(String)
    case apiError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub release data is invalid."
        case .emptyRelease:
            return "No GitHub release found for the configured repository."
        case .missingVersion(let version):
            return "Could not parse version from '\(version)'."
        case .noDownloadableZipAsset:
            return "No release zip asset was found in the latest GitHub release."
        case .repositoryNotFound(let repository):
            return "No published release was found for '\(repository)' (or the repository is unavailable)."
        case .apiError(let error):
            return "Update check failed: \(error.localizedDescription)"
        }
    }
}

struct GitHubReleaseChecker {
    struct Repository: Sendable {
        let owner: String
        let name: String

        var fullName: String { "\(owner)/\(name)" }
    }

    static let defaultRepository = Repository(owner: "hrayleung", name: "Jin")

    struct ReleasePayload: Decodable {
        struct AssetPayload: Decodable, Sendable {
            let name: String
            let browserDownloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: String?
        let publishedAt: String?
        let prerelease: Bool
        let assets: [AssetPayload]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case htmlURL = "html_url"
            case publishedAt = "published_at"
            case prerelease
            case assets
        }
    }

    private static let apiURLFormat = "https://api.github.com/repos/%@/releases/latest"
    private static let prereleaseURLFormat = "https://api.github.com/repos/%@/releases?per_page=1"
    private static let userAgent = "Jin macOS Update Checker"

    private static let sourceZipIndicators = ["source code", "source-code", "sourcecode", "src code", "source archive"]

    static let iso8601DateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso8601DateFormatterWithoutFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func checkForUpdate(
        repository: Repository = defaultRepository,
        currentInstalledVersion: String? = nil,
        bundle: Bundle = .main,
        networkManager: NetworkManager = NetworkManager(),
        allowPreRelease: Bool = false
    ) async throws -> GitHubReleaseCandidate {
        let endpoint = String(format: allowPreRelease ? prereleaseURLFormat : apiURLFormat, repository.fullName)
        guard let url = URL(string: endpoint) else {
            throw GitHubUpdateCheckError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let payload: ReleasePayload
        if allowPreRelease {
            let payloads = try await fetchReleasePayloads(
                using: request,
                networkManager: networkManager,
                repository: repository
            )
            guard let latest = payloads.first else { throw GitHubUpdateCheckError.emptyRelease }
            payload = latest
        } else {
            payload = try await fetchReleasePayload(
                using: request,
                networkManager: networkManager,
                repository: repository
            )
        }

        return try buildResult(
            from: payload,
            bundle: bundle,
            currentInstalledVersion: currentInstalledVersion
        )
    }

    static func parseVersion(_ rawVersion: String) -> UpdateVersion? {
        UpdateVersion(rawVersion)
    }

    static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }

        if let date = iso8601DateFormatter.date(from: value) {
            return date
        }

        return iso8601DateFormatterWithoutFraction.date(from: value)
    }

    static func pickZipAsset(
        from assets: [ReleasePayload.AssetPayload],
        appNameHint: String
    ) -> ReleasePayload.AssetPayload? {
        let zipAssets = assets.compactMap { asset -> ReleasePayload.AssetPayload? in
            guard let url = URL(string: asset.browserDownloadURL) else { return nil }
            guard url.pathExtension.lowercased() == "zip" else { return nil }
            return asset
        }

        let nonSourceZipAssets = zipAssets.filter { !isSourceZip($0) }
        guard !nonSourceZipAssets.isEmpty else { return nil }

        let candidate = nonSourceZipAssets.first(where: { asset in
            !isSourceZip(asset) && asset.name.localizedCaseInsensitiveContains(appNameHint)
        })

        if let candidate {
            return candidate
        }

        return nonSourceZipAssets.first
    }

    static func isSourceZip(_ asset: ReleasePayload.AssetPayload) -> Bool {
        let candidate = asset.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return sourceZipIndicators.contains { candidate.contains($0) }
    }

    static func buildResult(
        from payload: ReleasePayload,
        bundle: Bundle,
        currentInstalledVersion: String? = nil
    ) throws -> GitHubReleaseCandidate {
        guard !payload.assets.isEmpty else { throw GitHubUpdateCheckError.noDownloadableZipAsset }

        let appName = appName(from: bundle)
        guard let assetPayload = pickZipAsset(from: payload.assets, appNameHint: appName) else {
            throw GitHubUpdateCheckError.noDownloadableZipAsset
        }
        guard let downloadURL = URL(string: assetPayload.browserDownloadURL) else {
            throw GitHubUpdateCheckError.invalidResponse
        }
        guard let latestVersion = UpdateVersion(payload.tagName) else {
            throw GitHubUpdateCheckError.missingVersion(payload.tagName)
        }

        let currentVersionRaw = resolveCurrentVersion(
            bundleVersion: currentVersion(from: bundle),
            currentInstalledVersion: currentInstalledVersion
        )
        let currentVersion = currentVersionRaw.flatMap(UpdateVersion.init)

        let isUpdateAvailable: Bool
        if let currentVersion {
            isUpdateAvailable = latestVersion > currentVersion
        } else {
            isUpdateAvailable = false
        }

        return GitHubReleaseCandidate(
            tagName: payload.tagName,
            releaseTitle: payload.name ?? payload.tagName,
            body: payload.body ?? "",
            htmlURL: payload.htmlURL.flatMap(URL.init(string:)),
            publishedAt: parseDate(payload.publishedAt),
            asset: .init(
                name: assetPayload.name,
                downloadURL: downloadURL,
                isSourceCodeZip: isSourceZip(assetPayload)
            ),
            currentVersion: currentVersionRaw,
            currentVersionParsed: currentVersion,
            latestVersionParsed: latestVersion,
            isUpdateAvailable: isUpdateAvailable,
            isPrerelease: payload.prerelease
        )
    }

    static func resolveCurrentVersion(
        bundleVersion: String?,
        currentInstalledVersion: String?
    ) -> String? {
        let normalizedBundleVersion = normalizedVersionString(bundleVersion)
        if let bundleVersion = normalizedBundleVersion,
           !bundleVersion.isEmpty {
            return bundleVersion
        }

        let normalizedInstalledVersion = currentInstalledVersion?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let installedVersion = normalizedInstalledVersion,
           !installedVersion.isEmpty {
            return installedVersion
        }

        return nil
    }

    private static func normalizedVersionString(_ value: String?) -> String? {
        guard var normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else {
            return nil
        }

        if normalized.hasPrefix("v") || normalized.hasPrefix("V") {
            normalized.removeFirst()
        }

        return normalized
    }

    static func appName(from bundle: Bundle) -> String {
        let fallback = "Jin"
        if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displayName
        }

        if let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !shortVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return shortVersion
        }

        return fallback
    }

    static func currentVersion(from bundle: Bundle) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    private static func fetchReleasePayload(
        using request: URLRequest,
        networkManager: NetworkManager,
        repository: Repository
    ) async throws -> ReleasePayload {
        do {
            let (data, _) = try await networkManager.sendRequest(request)
            return try JSONDecoder().decode(ReleasePayload.self, from: data)
        } catch {
            throw mapError(error, repository: repository)
        }
    }

    private static func fetchReleasePayloads(
        using request: URLRequest,
        networkManager: NetworkManager,
        repository: Repository
    ) async throws -> [ReleasePayload] {
        do {
            let (data, _) = try await networkManager.sendRequest(request)
            return try JSONDecoder().decode([ReleasePayload].self, from: data)
        } catch {
            throw mapError(error, repository: repository)
        }
    }

    private static func mapError(_ error: Error, repository: Repository) -> GitHubUpdateCheckError {
        if let llmError = error as? LLMError,
           case let .providerError(code, message) = llmError,
           code == "404",
           message.localizedCaseInsensitiveContains("Not Found") {
            return .repositoryNotFound(repository.fullName)
        }

        return .apiError(error)
    }
}
