import SwiftUI
import AppKit

/// Isolated Settings sidebar. `SettingsView` also owns provider / plugin
/// state; leaving these rows inline would rebuild the glyphs on every
/// `@Query` and `ensureValidSelection()` write and replay their tint.
struct SettingsSidebarColumn: View {
    @Binding var selectedSection: SettingsView.SettingsSection?
    @Binding var searchText: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var accentRevision = 0

    var body: some View {
        List(
            SettingsView.SettingsSection.allCases,
            selection: SettingsSidebarSymbolSupport.sectionSelectionBinding($selectedSection)
        ) { section in
            // Selection binding drives the content column. A value
            // `NavigationLink` would activate on appear / re-select and
            // retint the `Label` through the sidebar's implicit animation.
            SettingsSidebarRow(section: section, iconColor: iconTint)
                .tag(section)
        }
        // Keep the native sidebar material. Painting an opaque `sidebarSurface`
        // (#ECECF0) over it read as a flat grey slab next to the near-white
        // `surface` (#FBFBFC) content and detail columns, and — unlike the real
        // material — never picked up the window's vibrancy. NavigationSplitView
        // draws its own column divider, so the hand-rolled hairline goes too.
        .listStyle(.sidebar)
        .listItemTint(.fixed(iconTint))
        .transaction(SettingsSidebarSymbolSupport.suppressAnimations)
        // `toolbar(removing:)` only takes effect on the *column's* content, not
        // on the NavigationSplitView itself — applied there it silently no-ops.
        // Settings has a fixed three-column layout, so the toggle is dead weight;
        // dropping it also empties the toolbar, collapsing the strip that was
        // stranding the button on its own row under the window controls.
        .toolbar(removing: .sidebarToggle)
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search settings")
        .onReceive(
            NotificationCenter.default.publisher(
                for: SettingsSidebarSymbolSupport.appleColorPreferencesChanged
            )
        ) { _ in
            accentRevision += 1
        }
    }

    private var iconTint: Color {
        _ = accentRevision
        return SettingsSidebarSymbolSupport.accentColor(
            colorScheme: colorScheme,
            contrast: colorSchemeContrast
        )
    }
}

struct SettingsSidebarRow: View {
    let section: SettingsView.SettingsSection
    let iconColor: Color

    var body: some View {
        Label {
            Text(section.rawValue)
        } icon: {
            Image(systemName: section.systemImage)
                .renderingMode(.original)
                .font(.system(
                    size: SettingsSidebarSymbolSupport.pointSize,
                    weight: SettingsSidebarSymbolSupport.weight
                ))
                .imageScale(.medium)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(iconColor)
                .contentTransition(.identity)
                .symbolEffectsRemoved()
        }
    }
}
