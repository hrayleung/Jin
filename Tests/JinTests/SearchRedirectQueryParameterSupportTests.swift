import Foundation
import XCTest
@testable import Jin

final class SearchRedirectQueryParameterSupportTests: XCTestCase {
    func testFirstDecodedURLUsesCaseInsensitiveKeyOrderAndSkipsMissingValues() {
        let queryItems = [
            URLQueryItem(name: "TARGET", value: nil),
            URLQueryItem(name: "AdUrl", value: "https%3A%2F%2Fexample.com%2Fdocs%3Fq%3Dswift")
        ]

        let url = SearchRedirectQueryParameterSupport.firstDecodedURL(
            from: queryItems,
            matchingAnyOf: ["target", "adurl"]
        )

        XCTAssertEqual(url?.absoluteString, "https://example.com/docs?q=swift")
    }

    func testFirstDecodedNonEmptyValueSkipsBlankValuesAndDecodesPercentEscapes() {
        let queryItems = [
            URLQueryItem(name: "q", value: "%20%20"),
            URLQueryItem(name: "QUERY", value: "swift%20ui")
        ]

        let value = SearchRedirectQueryParameterSupport.firstDecodedNonEmptyValue(
            from: queryItems,
            matchingAnyOf: ["q", "query"]
        )

        XCTAssertEqual(value, "swift ui")
    }

    func testFirstDecodedNonEmptyValueFallsBackToRawValueWhenPercentDecodingFails() {
        let queryItems = [
            URLQueryItem(name: "q", value: "100%")
        ]

        let value = SearchRedirectQueryParameterSupport.firstDecodedNonEmptyValue(
            from: queryItems,
            matchingAnyOf: ["q"]
        )

        XCTAssertEqual(value, "100%")
    }
}
