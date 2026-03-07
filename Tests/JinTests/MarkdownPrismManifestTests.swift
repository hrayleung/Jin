import XCTest
@testable import Jin

final class MarkdownPrismManifestTests: XCTestCase {
    private struct Manifest: Decodable {
        struct Language: Decodable {
            let id: String
            let name: String
            let aliases: [String]
        }

        let prismVersion: String
        let canonicalLanguages: [Language]
        let customAliases: [String: String]
    }

    private func loadManifest() throws -> Manifest {
        guard let url = Bundle.module.url(forResource: "markdown-prism-manifest", withExtension: "json") else {
            XCTFail("Missing markdown-prism-manifest.json in Jin resource bundle")
            throw NSError(domain: "MarkdownPrismManifestTests", code: 1)
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    func testManifestIncludesBroadLanguageCoverage() throws {
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
            "fortran-free-form",
            "objective-c",
            "proto",
            "terraform",
            "nushell",
            "fish",
            "mdx",
            "svelte",
            "vue",
            "tsx",
            "wgsl"
        ]

        let missing = expectedIDs.subtracting(supportedIDs)
        XCTAssertTrue(missing.isEmpty, "Missing languages in manifest: \(missing.sorted())")
        XCTAssertGreaterThan(manifest.canonicalLanguages.count, 250)
    }

    func testManifestCapturesOfficialAndCustomAliases() throws {
        let manifest = try loadManifest()

        XCTAssertFalse(manifest.prismVersion.isEmpty)
        XCTAssertEqual(manifest.customAliases["assembly"], "asm")
        XCTAssertEqual(manifest.customAliases["mermaid-svg"], "mermaid")
        XCTAssertEqual(manifest.customAliases["objectivec"], "objective-c")
        XCTAssertEqual(manifest.customAliases["nu"], "nushell")

        let aliasLookup = Dictionary(uniqueKeysWithValues: manifest.canonicalLanguages.map { ($0.id, Set($0.aliases)) })
        XCTAssertTrue(aliasLookup["javascript", default: []].contains("js"))
        XCTAssertTrue(aliasLookup["markdown", default: []].contains("md"))
        XCTAssertTrue(aliasLookup["bash", default: []].contains("sh"))
        XCTAssertTrue(aliasLookup["shellscript", default: []].contains("shell"))
        XCTAssertTrue(aliasLookup["shellsession", default: []].contains("terminal"))
    }
}
