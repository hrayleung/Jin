import Foundation

enum SearchSourceIdentitySupport {
    struct Identity: Equatable {
        let host: String
        let hostDisplay: String
        let usesGoogleGroundingRedirect: Bool
    }

    static func identity(rawHost: String, title: String?, kind: SearchSourceKind) -> Identity {
        let usesGoogleGroundingRedirect = isGoogleGroundingRedirectHost(rawHost)
        let host = if usesGoogleGroundingRedirect {
            domainCandidate(from: title) ?? rawHost
        } else {
            rawHost
        }

        return Identity(
            host: host,
            hostDisplay: hostDisplay(for: host, kind: kind),
            usesGoogleGroundingRedirect: usesGoogleGroundingRedirect
        )
    }

    static func hostDisplay(for host: String, kind: SearchSourceKind) -> String {
        if kind.isGoogleMaps {
            return "Google Maps"
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private static let googleGroundingRedirectHost = "vertexaisearch.cloud.google.com"

    private static func isGoogleGroundingRedirectHost(_ host: String) -> Bool {
        host.lowercased() == googleGroundingRedirectHost
    }

    private static func domainCandidate(from title: String?) -> String? {
        guard let title = title?.trimmedNonEmpty else { return nil }

        if let url = URL(string: title), let host = url.host?.trimmedNonEmpty {
            return host
        }

        guard !title.contains(" "), title.contains(".") else { return nil }
        return URL(string: "https://\(title)")?.host?.trimmedNonEmpty
    }
}
