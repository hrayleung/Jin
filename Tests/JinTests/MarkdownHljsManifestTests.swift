import XCTest
@testable import Jin

final class MarkdownHljsManifestTests: XCTestCase {
    private struct Manifest: Decodable {
        struct Language: Decodable {
            let id: String
            let name: String
            let aliases: [String]
        }

        let hljsVersion: String
        let canonicalLanguages: [Language]
        let customAliases: [String: String]
    }

    private func loadManifest() throws -> Manifest {
        guard let url = Bundle.module.url(forResource: "markdown-hljs-manifest", withExtension: "json") else {
            XCTFail("Missing markdown-hljs-manifest.json in Jin resource bundle")
            throw NSError(domain: "MarkdownHljsManifestTests", code: 1)
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    func testManifestIncludesCommonLanguages() throws {
        let manifest = try loadManifest()
        let supportedIDs = Set(manifest.canonicalLanguages.map(\.id))
        let expectedIDs: Set<String> = [
            "dart",
            "julia",
            "matlab",
            "crystal",
            "fsharp",
            "groovy",
            "ada",
            "tcl",
            "verilog",
            "vhdl",
            "scheme",
            "common-lisp",
            "fortran-free-form"
        ]

        let missing = expectedIDs.subtracting(supportedIDs)
        XCTAssertTrue(missing.isEmpty, "Missing languages in manifest: \(missing.sorted())")
    }

    func testManifestCapturesCustomAliases() throws {
        let manifest = try loadManifest()

        XCTAssertFalse(manifest.hljsVersion.isEmpty)
        XCTAssertEqual(manifest.customAliases["fortran"], "fortran-free-form")
        XCTAssertEqual(manifest.customAliases["assembly"], "asm")
        XCTAssertEqual(manifest.customAliases["docker"], "dockerfile")
        XCTAssertEqual(manifest.customAliases["mermaid-svg"], "mermaid")
    }
}
