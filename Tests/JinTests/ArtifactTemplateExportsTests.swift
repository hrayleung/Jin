import XCTest
@testable import Jin

final class ArtifactTemplateExportsTests: XCTestCase {
    func testArtifactTemplateIncludesLocalRuntime() throws {
        guard let url = Bundle.module.url(forResource: "artifact-template", withExtension: "html") else {
            XCTFail("Missing artifact-template.html in Jin resource bundle")
            return
        }

        let html = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(html.contains("artifact-runtime.js"))
        XCTAssertTrue(html.contains("artifact-root"))
        XCTAssertTrue(html.contains("Content-Security-Policy"))
        XCTAssertTrue(html.contains("connect-src 'none'"))
        XCTAssertTrue(html.contains("navigate-to 'none'"))
        XCTAssertTrue(html.contains("form-action 'none'"))
    }
}
