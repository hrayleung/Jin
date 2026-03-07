import XCTest
@testable import Jin

final class MarkdownShikiManifestTests: XCTestCase {
    private struct Manifest: Decodable {
        struct Language: Decodable {
            let id: String
            let name: String
            let aliases: [String]
        }

        let shikiVersion: String
        let starterLanguageIDs: [String]
        let canonicalLanguages: [Language]
        let customAliases: [String: String]
    }

    private func loadManifest() throws -> Manifest {
        guard let url = Bundle.module.url(forResource: "markdown-shiki-manifest", withExtension: "json") else {
            XCTFail("Missing markdown-shiki-manifest.json in Jin resource bundle")
            throw NSError(domain: "MarkdownShikiManifestTests", code: 1)
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    func testManifestIncludesLongTailLanguagesFromRegressionSet() throws {
        let manifest = try loadManifest()
        let supportedIDs = Set(manifest.canonicalLanguages.map(\.id))
        let expectedIDs: Set<String> = [
            "dart",
            "julia",
            "matlab",
            "cobol",
            "crystal",
            "fsharp",
            "groovy",
            "ada",
            "awk",
            "tcl",
            "verilog",
            "vhdl",
            "scheme",
            "common-lisp",
            "racket",
            "fortran-free-form"
        ]

        let missing = expectedIDs.subtracting(supportedIDs)
        XCTAssertTrue(missing.isEmpty, "Missing long-tail languages in manifest: \(missing.sorted())")
    }

    func testManifestKeepsStarterLanguagesForCommonRenderingPaths() throws {
        let manifest = try loadManifest()
        let starterIDs = Set(manifest.starterLanguageIDs)

        XCTAssertTrue(starterIDs.contains("markdown"))
        XCTAssertTrue(starterIDs.contains("mermaid"))
        XCTAssertTrue(starterIDs.contains("shellscript"))
        XCTAssertTrue(starterIDs.contains("swift"))
        XCTAssertTrue(starterIDs.contains("typescript"))
        XCTAssertTrue(starterIDs.contains("html"))
        XCTAssertTrue(starterIDs.contains("xml"))
        XCTAssertTrue(starterIDs.contains("json"))
    }

    func testManifestCapturesCustomAliasesForProblematicFenceNames() throws {
        let manifest = try loadManifest()

        XCTAssertFalse(manifest.shikiVersion.isEmpty)
        XCTAssertEqual(manifest.customAliases["fortran"], "fortran-free-form")
        XCTAssertEqual(manifest.customAliases["assembly"], "asm")
        XCTAssertEqual(manifest.customAliases["docker"], "dockerfile")
        XCTAssertEqual(manifest.customAliases["mermaid-svg"], "mermaid")
    }
}
