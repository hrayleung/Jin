import SwiftUI

/// Helpers that resolve design tokens against the current accessibility environment.
///
/// Two environments matter for surface chrome:
/// - `\.colorSchemeContrast` — switches `.standard` → `.increased` when the user
///   enables "Increase Contrast" in System Settings → Accessibility → Display.
/// - `\.accessibilityReduceTransparency` — `true` when the same panel's
///   "Reduce Transparency" toggle is on. Material backgrounds should fall back
///   to an opaque surface in that case.
enum JinThemeResolver {

    /// Hairline border that strengthens under increased contrast.
    static func borderHairline(contrast: ColorSchemeContrast) -> Color {
        contrast == .increased ? JinSemanticColor.borderEmphasized : JinSemanticColor.borderSubtle
    }

    /// Defined border. Currently constant; kept as a hook for a future
    /// `borderStrong` level if needed.
    static func borderDefined(contrast: ColorSchemeContrast) -> Color {
        JinSemanticColor.borderEmphasized
    }
}

extension View {
    /// Paints an adaptive background that uses a SwiftUI `Material` by default
    /// and falls back to an opaque token color when Reduce Transparency is on.
    func jinAdaptiveBackground<S: Shape>(
        _ shape: S,
        material: Material = .regularMaterial,
        fallback: Color = JinSemanticColor.raisedSurface
    ) -> some View {
        modifier(JinAdaptiveBackgroundModifier(shape: shape, material: material, fallback: fallback))
    }
}

private struct JinAdaptiveBackgroundModifier<S: Shape>: ViewModifier {
    let shape: S
    let material: Material
    let fallback: Color

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(shape.fill(fallback))
        } else {
            content.background(shape.fill(material))
        }
    }
}
