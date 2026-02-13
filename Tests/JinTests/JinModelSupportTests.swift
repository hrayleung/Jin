import XCTest
@testable import Jin

final class JinModelSupportTests: XCTestCase {
    func testFireworksGLM5IsMarkedAsFullySupported() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "fireworks/glm-5"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "accounts/fireworks/models/glm-5"))
    }
}
