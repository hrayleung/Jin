import XCTest
@testable import Jin

final class JinTypographyTests: XCTestCase {
    func testNormalizedFontPreferenceTreatsBlankAsSystemDefault() {
        XCTAssertEqual(
            JinTypography.normalizedFontPreference("   \n\t"),
            JinTypography.systemFontPreferenceValue
        )
    }

    func testClampedChatMessageScaleBounds() {
        XCTAssertEqual(
            JinTypography.clampedChatMessageScale(0.2),
            JinTypography.chatMessageScaleRange.lowerBound,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            JinTypography.clampedChatMessageScale(2.0),
            JinTypography.chatMessageScaleRange.upperBound,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            JinTypography.clampedChatMessageScale(1.1),
            1.1,
            accuracy: 0.0001
        )
    }

    func testSystemDefaultDisplayName() {
        XCTAssertEqual(
            JinTypography.displayName(for: JinTypography.systemFontPreferenceValue),
            JinTypography.defaultFontDisplayName
        )
    }

    func testAppearanceLabels() {
        XCTAssertEqual(AppAppearanceMode.system.label, "System")
        XCTAssertEqual(AppAppearanceMode.light.label, "Light")
        XCTAssertEqual(AppAppearanceMode.dark.label, "Dark")
    }
}
