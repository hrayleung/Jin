import Foundation

enum JinResourceBundle {
    private static let bundleName = "Jin_Jin.bundle"

    static let bundle: Bundle = {
        for candidateURL in candidateURLs() {
            if let bundle = Bundle(url: candidateURL) {
                return bundle
            }
        }

        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        fatalError("Unable to locate \(bundleName).")
        #endif
    }()

    static func url(forResource name: String, withExtension ext: String?) -> URL? {
        bundle.url(forResource: name, withExtension: ext)
    }

    private static func candidateURLs() -> [URL] {
        var urls: [URL] = []

        if let resourcesURL = Bundle.main.resourceURL {
            urls.append(resourcesURL.appendingPathComponent(bundleName, isDirectory: true))
        }

        urls.append(Bundle.main.bundleURL.appendingPathComponent(bundleName, isDirectory: true))

        if let executableURL = Bundle.main.executableURL {
            let executableDirectory = executableURL.deletingLastPathComponent()
            urls.append(executableDirectory.appendingPathComponent(bundleName, isDirectory: true))
        }

        return deduplicated(urls)
    }

    private static func deduplicated(_ urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        return urls.filter { url in
            seenPaths.insert(url.standardizedFileURL.path).inserted
        }
    }
}
