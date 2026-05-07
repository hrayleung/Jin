import XCTest
@testable import Jin

final class ContextCacheControlsTests: XCTestCase {
    func testContextCacheTTLDecodingNormalizesStringValues() throws {
        XCTAssertEqual(try decodedTTL(from: #"" 5M\n ""#), .minutes5)
        XCTAssertEqual(try decodedTTL(from: #"" custom: 90\n ""#), .customSeconds(90))
        XCTAssertEqual(try decodedTTL(from: #"" \n\t ""#), .providerDefault)
    }

    func testContextCacheTTLDecodingClampsNumericValues() throws {
        XCTAssertEqual(try decodedTTL(from: #"0"#), .customSeconds(1))
        XCTAssertEqual(try decodedTTL(from: #"120"#), .customSeconds(120))
    }

    private func decodedTTL(from json: String) throws -> ContextCacheTTL {
        try JSONDecoder().decode(ContextCacheTTL.self, from: Data(json.utf8))
    }
}
