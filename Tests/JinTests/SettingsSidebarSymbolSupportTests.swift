import AppKit
import SwiftUI
import XCTest
@testable import Jin

final class SettingsSidebarSymbolSupportTests: XCTestCase {
    func testSuppressedTransactionDisablesImplicitAnimation() {
        var transaction = Transaction(animation: .default)
        transaction.disablesAnimations = false

        SettingsSidebarSymbolSupport.suppressAnimations(&transaction)

        XCTAssertNil(transaction.animation)
        XCTAssertTrue(transaction.disablesAnimations)
    }

    func testSectionSelectionBindingNeverWritesNil() {
        var selected: SettingsView.SettingsSection? = .providers
        let binding = SettingsSidebarSymbolSupport.sectionSelectionBinding(
            Binding(
                get: { selected },
                set: { selected = $0 }
            )
        )

        binding.wrappedValue = nil
        XCTAssertEqual(selected, .providers)

        binding.wrappedValue = .plugins
        XCTAssertEqual(selected, .plugins)
        XCTAssertEqual(binding.wrappedValue, .plugins)
    }

    func testSectionSelectionBindingReadsProvidersWhenNil() {
        var selected: SettingsView.SettingsSection?
        let binding = SettingsSidebarSymbolSupport.sectionSelectionBinding(
            Binding(
                get: { selected },
                set: { selected = $0 }
            )
        )

        XCTAssertEqual(binding.wrappedValue, .providers)
    }

    func testResolvedAccentColorIsComponentBasedSRGB() {
        let color = SettingsSidebarSymbolSupport.resolvedAccentNSColor()

        XCTAssertEqual(color.type, .componentBased)
        XCTAssertEqual(color.colorSpace, .sRGB)
        XCTAssertNotEqual(color.type, .catalog)
    }

    func testResolvedAccentColorMatchesControlAccentComponents() {
        let appearance = SettingsSidebarSymbolSupport.appearance(for: .light)
        let resolved = SettingsSidebarSymbolSupport.resolvedAccentNSColor(appearance: appearance)
        var expected = NSColor.systemBlue
        appearance.performAsCurrentDrawingAppearance {
            expected = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
        }

        XCTAssertEqual(resolved.redComponent, expected.redComponent, accuracy: 0.001)
        XCTAssertEqual(resolved.greenComponent, expected.greenComponent, accuracy: 0.001)
        XCTAssertEqual(resolved.blueComponent, expected.blueComponent, accuracy: 0.001)
        XCTAssertEqual(resolved.alphaComponent, expected.alphaComponent, accuracy: 0.001)
    }

    func testDarkAppearanceIsDarkAqua() {
        XCTAssertEqual(
            SettingsSidebarSymbolSupport.appearance(for: .dark).name,
            .darkAqua
        )
        XCTAssertEqual(
            SettingsSidebarSymbolSupport.appearance(for: .light).name,
            .aqua
        )
    }

    func testHighContrastAppearanceResolvesWithoutCrashing() {
        let dark = SettingsSidebarSymbolSupport.appearance(for: .dark, contrast: .increased)
        let light = SettingsSidebarSymbolSupport.appearance(for: .light, contrast: .increased)
        let allowedDark: Set<NSAppearance.Name> = [
            .darkAqua, .accessibilityHighContrastDarkAqua
        ]
        let allowedLight: Set<NSAppearance.Name> = [
            .aqua, .accessibilityHighContrastAqua
        ]

        XCTAssertTrue(allowedDark.contains(dark.name))
        XCTAssertTrue(allowedLight.contains(light.name))
    }

    func testSettingsSidebarDoesNotUseAutomaticSystemImageLabels() throws {
        let settingsView = try sourceFile("Sources/UI/SettingsView.swift")
        XCTAssertFalse(settingsView.contains("Label(section.rawValue, systemImage:"))
        XCTAssertTrue(settingsView.contains("SettingsSidebarColumn("))

        let sidebar = try sourceFile("Sources/UI/SettingsSidebarColumn.swift")
        XCTAssertFalse(sidebar.contains("NavigationLink(value:"))
        XCTAssertFalse(sidebar.contains("Label(section.rawValue, systemImage:"))
        XCTAssertTrue(sidebar.contains("symbolEffectsRemoved"))
        XCTAssertTrue(sidebar.contains("listItemTint(.fixed"))
        XCTAssertTrue(sidebar.contains("symbolRenderingMode(.monochrome)"))
        XCTAssertTrue(sidebar.contains("renderingMode(.original)"))
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        try String(contentsOfFile: relativePath, encoding: .utf8)
    }
}
