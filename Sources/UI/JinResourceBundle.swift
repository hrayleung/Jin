import Foundation

enum JinResourceBundle {
    private static let bundleName = "Jin_Jin.bundle"
    private static let fallbackSearchDepth = 5

    static let bundle: Bundle? = {
        for candidateURL in candidateURLs() {
            if let bundle = Bundle(url: candidateURL) {
                return bundle
            }
        }

        return nil
    }()

    static func url(forResource name: String, withExtension ext: String?) -> URL? {
        bundle?.url(forResource: name, withExtension: ext)
    }

    private static func candidateURLs() -> [URL] {
        var urls: [URL] = []

        if let resourcesURL = Bundle.main.resourceURL {
            urls.append(resourcesURL.appendingPathComponent(bundleName, isDirectory: true))
        }

        let mainBundleURL = Bundle.main.bundleURL.standardizedFileURL
        urls.append(mainBundleURL.appendingPathComponent(bundleName, isDirectory: true))

        let mainResourceURL = mainBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(bundleName, isDirectory: true)
        urls.append(mainResourceURL)
        urls.append(mainBundleURL
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(bundleName, isDirectory: true))

        if let executableURL = Bundle.main.executableURL {
            let executableDirectory = executableURL.deletingLastPathComponent()
            urls.append(executableDirectory.appendingPathComponent(bundleName, isDirectory: true))
            urls.append(
                executableDirectory
                    .appendingPathComponent("Contents", isDirectory: true)
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent(bundleName, isDirectory: true)
            )
        }

        for ancestor in ancestorURLs(startingAt: mainBundleURL, depth: fallbackSearchDepth) {
            urls.append(ancestor.appendingPathComponent(bundleName, isDirectory: true))
            urls.append(
                ancestor
                    .appendingPathComponent("Contents", isDirectory: true)
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent(bundleName, isDirectory: true)
            )
            urls.append(
                ancestor
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent(bundleName, isDirectory: true)
            )
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let cwdDirectory = cwd.standardizedFileURL
        urls.append(cwdDirectory.appendingPathComponent(bundleName, isDirectory: true))
        urls.append(
            cwdDirectory
                .appendingPathComponent(".build", isDirectory: true)
                .appendingPathComponent(bundleName, isDirectory: true)
        )
        for buildDirectory in ["arm64-apple-macosx", "x86_64-apple-macosx"] {
            for configuration in ["debug", "release"] {
                urls.append(
                    cwdDirectory
                        .appendingPathComponent(".build", isDirectory: true)
                        .appendingPathComponent(buildDirectory, isDirectory: true)
                        .appendingPathComponent(configuration, isDirectory: true)
                        .appendingPathComponent(bundleName, isDirectory: true)
                )
            }
        }

        return deduplicated(urls)
    }

    private static func ancestorURLs(startingAt url: URL, depth: Int) -> [URL] {
        guard depth > 0 else { return [] }

        var ancestors: [URL] = []
        var cursor = url
        for _ in 0..<depth {
            ancestors.append(cursor)
            let parent = cursor.deletingLastPathComponent()
            if parent == cursor {
                break
            }
            cursor = parent
        }
        return ancestors
    }

    private static func deduplicated(_ urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        return urls.filter { url in
            seenPaths.insert(url.standardizedFileURL.path).inserted
        }
    }
}
