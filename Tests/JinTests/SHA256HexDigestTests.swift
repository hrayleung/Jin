import Foundation
import XCTest
@testable import Jin

final class SHA256HexDigestTests: XCTestCase {
    func testStringDigestUsesLowercaseHexEncoding() {
        XCTAssertEqual(
            SHA256HexDigest.string("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testDataDigestMatchesStringDigestForUTF8Input() {
        XCTAssertEqual(
            SHA256HexDigest.data(Data("abc".utf8)),
            SHA256HexDigest.string("abc")
        )
    }

    func testDataPrefixReturnsRequestedDigestByteCountAsHex() {
        XCTAssertEqual(
            SHA256HexDigest.dataPrefix(Data("abc".utf8), byteCount: 8),
            "ba7816bf8f01cfea"
        )
    }

    func testDataPrefixClampsNegativeByteCountToEmptyDigest() {
        XCTAssertEqual(
            SHA256HexDigest.dataPrefix(Data("abc".utf8), byteCount: -1),
            ""
        )
    }
}
