import XCTest
@testable import Jin

final class MessageImageCacheKeySupportTests: XCTestCase {
    func testInlineImageFingerprintDiffersForSameLengthData() {
        let first = Data([0x00, 0x01, 0x02, 0x03])
        let second = Data([0xFF, 0xEE, 0xDD, 0xCC])

        XCTAssertEqual(first.count, second.count)
        XCTAssertNotEqual(
            MessageImageCacheKeySupport.inlineDataFingerprint(first),
            MessageImageCacheKeySupport.inlineDataFingerprint(second)
        )
    }
}
