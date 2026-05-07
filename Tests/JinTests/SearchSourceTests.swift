import XCTest
@testable import Jin

final class SearchSourceTests: XCTestCase {
    func testURLNormalizerTrimsBlankValuesAndAddsHTTPSWhenMissing() {
        XCTAssertNil(SearchURLNormalizer.normalize(" \n\t "))
        XCTAssertEqual(
            SearchURLNormalizer.normalize(" example.com/docs "),
            "https://example.com/docs"
        )
        XCTAssertEqual(
            SearchURLNormalizer.normalize(" https://example.com/docs "),
            "https://example.com/docs"
        )
    }

    func testInitNormalizesURLAndWebIdentity() throws {
        let source = try XCTUnwrap(
            SearchSource(
                rawURL: "  www.example.com/docs/search?q=swift  ",
                title: " Example Docs ",
                previewText: " Provider\npreview "
            )
        )

        XCTAssertEqual(source.id, "https://www.example.com/docs/search?q=swift")
        XCTAssertEqual(source.canonicalURLString, "https://www.example.com/docs/search?q=swift")
        XCTAssertEqual(source.title, "Example Docs")
        XCTAssertEqual(source.previewText, "Provider preview")
        XCTAssertEqual(source.host, "www.example.com")
        XCTAssertEqual(source.hostDisplay, "example.com")
        XCTAssertEqual(source.kind, .web)
        XCTAssertFalse(source.usesGoogleGroundingRedirect)
    }

    func testInitUsesGroundingRedirectTitleAsResolvedHostWhenTitleIsDomain() throws {
        let source = try XCTUnwrap(
            SearchSource(
                rawURL: "https://vertexaisearch.cloud.google.com/grounding-api-redirect?q=apple",
                title: "developer.apple.com",
                previewText: nil
            )
        )

        XCTAssertEqual(source.host, "developer.apple.com")
        XCTAssertEqual(source.hostDisplay, "developer.apple.com")
        XCTAssertTrue(source.usesGoogleGroundingRedirect)
    }

    func testInitUsesGroundingRedirectTitleURLHostWhenAvailable() throws {
        let source = try XCTUnwrap(
            SearchSource(
                rawURL: "https://vertexaisearch.cloud.google.com/grounding-api-redirect?q=swiftui",
                title: "https://developer.apple.com/documentation/swiftui",
                previewText: nil
            )
        )

        XCTAssertEqual(source.host, "developer.apple.com")
        XCTAssertEqual(source.hostDisplay, "developer.apple.com")
        XCTAssertTrue(source.usesGoogleGroundingRedirect)
    }

    func testInitKeepsGroundingRedirectHostWhenTitleIsNotDomainLike() throws {
        let source = try XCTUnwrap(
            SearchSource(
                rawURL: "https://vertexaisearch.cloud.google.com/grounding-api-redirect?q=apple",
                title: "Apple Developer Documentation",
                previewText: nil
            )
        )

        XCTAssertEqual(source.host, "vertexaisearch.cloud.google.com")
        XCTAssertEqual(source.hostDisplay, "vertexaisearch.cloud.google.com")
        XCTAssertTrue(source.usesGoogleGroundingRedirect)
    }

    func testMapsSourceUsesMapsDisplayAndTrimmedPlaceID() throws {
        let source = try XCTUnwrap(
            SearchSource(
                rawURL: "https://maps.google.com/?q=Apple+Park",
                title: "Apple Park",
                previewText: nil,
                kind: .googleMaps,
                mapsPlaceID: " place-123 "
            )
        )

        XCTAssertEqual(source.host, "maps.google.com")
        XCTAssertEqual(source.hostDisplay, "Google Maps")
        XCTAssertEqual(source.kind, .googleMaps)
        XCTAssertEqual(source.mapsPlaceID, "place-123")
    }

    func testMergedPrefersNewTitleLongerPreviewAndMapsIdentity() throws {
        let source = try XCTUnwrap(
            SearchSource(
                rawURL: "https://example.com",
                title: "Old title",
                previewText: "short"
            )
        )

        let merged = source.merged(
            withTitle: " New title ",
            previewText: "A longer preview",
            kind: .googleMaps,
            mapsPlaceID: " place-456 "
        )

        XCTAssertEqual(merged.title, "New title")
        XCTAssertEqual(merged.previewText, "A longer preview")
        XCTAssertEqual(merged.kind, .googleMaps)
        XCTAssertEqual(merged.hostDisplay, "Google Maps")
        XCTAssertEqual(merged.mapsPlaceID, "place-456")
    }
}
