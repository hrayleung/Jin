import XCTest
import Foundation
@testable import Jin

final class NetworkManagerTests: XCTestCase {
    func testDefaultSessionConfigurationUsesLongRunningTimeouts() {
        let configuration = NetworkManager.makeDefaultSessionConfiguration()

        XCTAssertEqual(
            configuration.timeoutIntervalForRequest,
            NetworkManager.defaultRequestTimeoutInterval
        )
        XCTAssertEqual(
            configuration.timeoutIntervalForResource,
            NetworkManager.defaultResourceTimeoutInterval
        )
        XCTAssertGreaterThan(
            configuration.timeoutIntervalForRequest,
            URLSession.shared.configuration.timeoutIntervalForRequest
        )
    }
}
