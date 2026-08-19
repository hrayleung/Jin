import SwiftUI

/// One shared label column for every label + control settings row.
///
/// `LabeledContent` inside a grouped `Form` picks its own label/content split
/// per row, derived from the *control's* ideal width. A row holding a long
/// monospaced URL therefore shoves its field hard left (right up against the
/// label) while a row holding a short text field leaves the value floating near
/// the middle — so no two rows in the same card start at the same x. Settings
/// rows opt out of that: each reports its label's intrinsic width, the page
/// resolves the widest, and every row pins its label to that width. Labels line
/// up on one edge, fields and controls on another.
enum JinSettingsMetrics {
    /// Floor for the shared label column. Keeps short-label cards
    /// (Name / Icon / Base URL) on the same grid as the rest of the app, and is
    /// wide enough for the longest label we ship so the fallback value below
    /// never truncates.
    static let labelColumnMinWidth: CGFloat = 128

    /// Ceiling, so one unusually long label can't squeeze the control column.
    /// Labels wider than this truncate instead of stealing the field's width.
    static let labelColumnMaxWidth: CGFloat = 200

    /// Gutter between the label column and the control column.
    static let labelColumnSpacing: CGFloat = JinSpacing.medium
}

struct JinSettingsLabelWidthPreference: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct JinSettingsLabelColumnWidthKey: EnvironmentKey {
    static let defaultValue = JinSettingsMetrics.labelColumnMinWidth
}

extension EnvironmentValues {
    var jinSettingsLabelColumnWidth: CGFloat {
        get { self[JinSettingsLabelColumnWidthKey.self] }
        set { self[JinSettingsLabelColumnWidthKey.self] = newValue }
    }
}

extension View {
    /// Resolves one label column for every settings row in this subtree.
    ///
    /// Surfaces that don't install a resolver (cards inside sheets) still get a
    /// consistent grid — they just use the floor width rather than a measured
    /// one.
    func jinSettingsLabelColumn() -> some View {
        modifier(JinSettingsLabelColumnResolver())
    }
}

private struct JinSettingsLabelColumnResolver: ViewModifier {
    @State private var resolvedWidth = JinSettingsMetrics.labelColumnMinWidth

    func body(content: Content) -> some View {
        content
            .environment(\.jinSettingsLabelColumnWidth, resolvedWidth)
            .onPreferenceChange(JinSettingsLabelWidthPreference.self) { widest in
                // Labels are measured unconstrained (see `JinSettingsRowLabel`),
                // so the reported width never depends on the width we hand back
                // — this settles after one pass instead of oscillating.
                let clamped = min(
                    max(widest.rounded(.up), JinSettingsMetrics.labelColumnMinWidth),
                    JinSettingsMetrics.labelColumnMaxWidth
                )
                MainActor.assumeIsolated {
                    guard abs(clamped - resolvedWidth) > 0.5 else { return }
                    resolvedWidth = clamped
                }
            }
    }
}

/// The label half of a settings row: renders at the column width resolved for
/// the surrounding page and reports its own intrinsic width upward.
struct JinSettingsRowLabel: View {
    let title: String

    @Environment(\.jinSettingsLabelColumnWidth) private var columnWidth

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: columnWidth, alignment: .leading)
            .background(alignment: .leading) { intrinsicWidthProbe }
    }

    /// Measures the label *unconstrained*. Measuring the rendered copy instead
    /// would feed the applied width straight back into the resolver.
    private var intrinsicWidthProbe: some View {
        Text(title)
            .fixedSize()
            .hidden()
            .accessibilityHidden(true)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: JinSettingsLabelWidthPreference.self,
                        value: proxy.size.width
                    )
                }
            }
    }
}
