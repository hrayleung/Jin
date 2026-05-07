import XCTest
@testable import Jin

final class SearchActivityPresentationBuilderTests: XCTestCase {
    func testBuildDeduplicatesQueriesCaseInsensitivelyAndPreservesFirstSpelling() {
        let output = SearchActivityPresentationBuilder.build(
            from: [
                activity(
                    id: "one",
                    arguments: [
                        "queries": AnyCodable([" SwiftUI ", "swiftui", "MCP"])
                    ]
                ),
                activity(
                    id: "two",
                    arguments: [
                        "query": AnyCodable(" mcp ")
                    ]
                )
            ]
        )

        XCTAssertEqual(output.queries, ["SwiftUI", "MCP"])
    }

    func testBuildExtractsSingleURLAndSourceArraySources() {
        let output = SearchActivityPresentationBuilder.build(
            from: [
                activity(
                    id: "single",
                    arguments: [
                        "url": AnyCodable("https://example.com/one"),
                        "title": AnyCodable("Example One"),
                        "snippet": AnyCodable("Single snippet")
                    ]
                ),
                activity(
                    id: "array",
                    arguments: [
                        "sources": AnyCodable([
                            [
                                "url": "https://example.com/two",
                                "title": "Example Two",
                                "summary": "Array summary"
                            ]
                        ])
                    ]
                )
            ]
        )

        XCTAssertEqual(output.sources.map(\.canonicalURLString), [
            "https://example.com/one",
            "https://example.com/two"
        ])
        XCTAssertEqual(output.sources.map(\.title), ["Example One", "Example Two"])
    }

    func testBuildExtractsNestedSourcePayloadsAndMapsMetadata() {
        let output = SearchActivityPresentationBuilder.build(
            from: [
                activity(
                    id: "nested",
                    arguments: [
                        "sources": AnyCodable([
                            [
                                "source": [
                                    "url": " https://example.com/place ",
                                    "title": " Example Place ",
                                    "description": " Nested description ",
                                    "type": "google_maps",
                                    "place_id": " place-123 "
                                ]
                            ]
                        ])
                    ]
                )
            ]
        )

        XCTAssertEqual(output.sources.map(\.canonicalURLString), ["https://example.com/place"])
        XCTAssertEqual(output.sources.first?.title, "Example Place")
        XCTAssertEqual(output.sources.first?.previewText, "Nested description")
        XCTAssertEqual(output.sources.first?.kind, .googleMaps)
        XCTAssertEqual(output.sources.first?.mapsPlaceID, "place-123")
    }

    func testBuildExtractsDirectSourceMapsMetadata() {
        let output = SearchActivityPresentationBuilder.build(
            from: [
                activity(
                    id: "direct-maps",
                    arguments: [
                        "url": AnyCodable("https://maps.google.com/?q=Apple+Park"),
                        "title": AnyCodable("Apple Park"),
                        "sourceKind": AnyCodable("google_maps"),
                        "mapsPlaceID": AnyCodable(" place-456 ")
                    ]
                )
            ]
        )

        XCTAssertEqual(output.sources.map(\.canonicalURLString), ["https://maps.google.com/?q=Apple+Park"])
        XCTAssertEqual(output.sources.first?.title, "Apple Park")
        XCTAssertEqual(output.sources.first?.kind, .googleMaps)
        XCTAssertEqual(output.sources.first?.mapsPlaceID, "place-456")
    }

    func testBuildMergesDuplicateSourcesPreferringNewerTitleAndLongerPreview() {
        let output = SearchActivityPresentationBuilder.build(
            from: [
                activity(
                    id: "old",
                    arguments: [
                        "url": AnyCodable("https://example.com/page"),
                        "title": AnyCodable("Old Title"),
                        "snippet": AnyCodable("Short")
                    ]
                ),
                activity(
                    id: "new",
                    arguments: [
                        "url": AnyCodable("https://example.com/page"),
                        "title": AnyCodable("New Title"),
                        "snippet": AnyCodable("Longer preview")
                    ]
                )
            ]
        )

        XCTAssertEqual(output.sources.count, 1)
        XCTAssertEqual(output.sources.first?.title, "New Title")
        XCTAssertEqual(output.sources.first?.previewText, "Longer preview")
    }

    private func activity(
        id: String,
        type: String = "search",
        status: SearchActivityStatus = .completed,
        arguments: [String: AnyCodable] = [:],
        outputIndex: Int? = nil,
        sequenceNumber: Int? = nil
    ) -> SearchActivity {
        SearchActivity(
            id: id,
            type: type,
            status: status,
            arguments: arguments,
            outputIndex: outputIndex,
            sequenceNumber: sequenceNumber
        )
    }
}
