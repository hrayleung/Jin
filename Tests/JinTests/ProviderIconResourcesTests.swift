import XCTest
@testable import Jin

final class ProviderIconResourcesTests: XCTestCase {
    func testBundledProviderIconsIncludeAllCatalogEntries() {
        var missing: [String] = []

        for icon in LobeProviderIconCatalog.all {
            if icon.localPNGImage(useDarkMode: false) == nil {
                missing.append("light:\(icon.id)")
            }
            if icon.localPNGImage(useDarkMode: true) == nil {
                missing.append("dark:\(icon.id)")
            }
        }

        XCTAssertTrue(missing.isEmpty, "Missing bundled provider icons: \(missing.joined(separator: ", "))")
    }
}
