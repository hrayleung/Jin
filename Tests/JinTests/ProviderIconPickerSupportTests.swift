import XCTest
@testable import Jin

final class ProviderIconPickerSupportTests: XCTestCase {
    private let icons = [
        LobeProviderIcon(id: "OpenAI", docsSlug: "open-ai", filename: "openai.svg"),
        LobeProviderIcon(id: "GithubCopilot", docsSlug: "github-copilot", filename: "githubcopilot.svg"),
        LobeProviderIcon(id: "Anthropic", docsSlug: "anthropic", filename: "anthropic.svg")
    ]

    func testNormalizedIconIDTrimsAndDropsBlankValues() {
        XCTAssertNil(ProviderIconPickerSupport.normalizedIconID(nil))
        XCTAssertNil(ProviderIconPickerSupport.normalizedIconID("  "))
        XCTAssertEqual(ProviderIconPickerSupport.normalizedIconID(" OpenAI "), "OpenAI")
    }

    func testActiveIconAndDisplayLabelMatchPickerFallbackRules() {
        XCTAssertEqual(
            ProviderIconPickerSupport.activeIconID(
                selectedIconID: "  ",
                defaultIconID: " OpenAI "
            ),
            "OpenAI"
        )
        XCTAssertNil(
            ProviderIconPickerSupport.activeIconID(
                selectedIconID: "  ",
                defaultIconID: " \n "
            )
        )
        XCTAssertEqual(
            ProviderIconPickerSupport.activeIconID(
                selectedIconID: " Anthropic ",
                defaultIconID: "OpenAI"
            ),
            "Anthropic"
        )
        XCTAssertEqual(
            ProviderIconPickerSupport.displayLabel(
                selectedIconID: "  ",
                defaultIconID: " OpenAI "
            ),
            "Default (OpenAI)"
        )
        XCTAssertEqual(
            ProviderIconPickerSupport.displayLabel(
                selectedIconID: nil,
                defaultIconID: nil
            ),
            "Choose..."
        )
        XCTAssertEqual(
            ProviderIconPickerSupport.displayLabel(
                selectedIconID: nil,
                defaultIconID: " \n "
            ),
            "Choose..."
        )
        XCTAssertEqual(
            ProviderIconPickerSupport.displayLabel(
                selectedIconID: " Anthropic ",
                defaultIconID: "OpenAI"
            ),
            "Anthropic"
        )
    }

    func testFilteredIconsSearchesIDsAndDocsSlugsCaseInsensitively() {
        XCTAssertEqual(
            ProviderIconPickerSupport.filteredIcons(from: icons, searchText: "  ").map(\.id),
            ["OpenAI", "GithubCopilot", "Anthropic"]
        )
        XCTAssertEqual(
            ProviderIconPickerSupport.filteredIcons(from: icons, searchText: " COPILOT ").map(\.id),
            ["GithubCopilot"]
        )
        XCTAssertEqual(
            ProviderIconPickerSupport.filteredIcons(from: icons, searchText: "open-ai").map(\.id),
            ["OpenAI"]
        )
    }

    func testSelectionHelpersPreserveExplicitDefaultIconSelection() {
        XCTAssertTrue(ProviderIconPickerSupport.isDefaultSelected(nil))
        XCTAssertTrue(ProviderIconPickerSupport.isDefaultSelected("  "))
        XCTAssertFalse(ProviderIconPickerSupport.isDefaultSelected("OpenAI"))
        XCTAssertTrue(
            ProviderIconPickerSupport.isSelected(
                icon: icons[0],
                selectedIconID: " openai "
            )
        )
        XCTAssertFalse(
            ProviderIconPickerSupport.isSelected(
                icon: icons[1],
                selectedIconID: "OpenAI"
            )
        )
    }
}
