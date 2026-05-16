#if DEBUG
import SwiftUI

/// Visual reference for every semantic color token in `JinSemanticColor`.
/// Used as a Xcode preview to eyeball the surface hierarchy and to capture
/// before/after screenshots when iterating on the design system.
///
/// Render via Xcode preview only — never embedded in the shipped UI.
struct JinDesignSystemPreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JinSpacing.large) {
                surfaceSection
                tonalSection
                borderSection
                shadowSection
                selectedSection
                variantSection
                modifierSection
            }
            .padding(JinSpacing.xLarge)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .background(JinSemanticColor.surface)
        .frame(minWidth: 760, minHeight: 720)
    }

    // MARK: - Sections

    private var surfaceSection: some View {
        section(title: "Surfaces") {
            swatch("canvas", JinSemanticColor.canvas)
            swatch("surface (page)", JinSemanticColor.surface)
            swatch("panelSurface", JinSemanticColor.panelSurface)
            swatch("raisedSurface", JinSemanticColor.raisedSurface)
            swatch("textSurface", JinSemanticColor.textSurface)
        }
    }

    private var tonalSection: some View {
        section(title: "Tonal") {
            swatch("subtleSurface", JinSemanticColor.subtleSurface)
            swatch("subtleSurfaceStrong", JinSemanticColor.subtleSurfaceStrong)
            swatch("accentSurface", JinSemanticColor.accentSurface)
        }
    }

    private var borderSection: some View {
        section(title: "Borders") {
            borderSwatch("borderSubtle", JinSemanticColor.borderSubtle)
            borderSwatch("borderEmphasized", JinSemanticColor.borderEmphasized)
            borderSwatch("separator (alias)", JinSemanticColor.separator)
        }
    }

    private var shadowSection: some View {
        section(title: "Shadows (preview only)") {
            HStack(spacing: JinSpacing.medium) {
                shadowSwatch("shadowSubtle", JinSemanticColor.shadowSubtle, radius: 8)
                shadowSwatch("shadowElevated", JinSemanticColor.shadowElevated, radius: 16)
            }
        }
    }

    private var selectedSection: some View {
        section(title: "Selected / Accent") {
            HStack(spacing: JinSpacing.small) {
                Text("Selected")
                    .padding(.horizontal, JinSpacing.medium)
                    .padding(.vertical, JinSpacing.small)
                    .background(JinSemanticColor.selectedSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: JinRadius.small)
                            .stroke(JinSemanticColor.selectedStroke, lineWidth: JinStrokeWidth.regular)
                    )

                Text("Accent")
                    .padding(.horizontal, JinSpacing.medium)
                    .padding(.vertical, JinSpacing.small)
                    .background(JinSemanticColor.accentSurface)
            }
        }
    }

    private var variantSection: some View {
        section(title: "jinSurface variants") {
            VStack(alignment: .leading, spacing: JinSpacing.small) {
                surfaceVariantRow(.neutral, label: ".neutral")
                surfaceVariantRow(.raised, label: ".raised  (has shadow)")
                surfaceVariantRow(.selected, label: ".selected")
                surfaceVariantRow(.subtle, label: ".subtle")
                surfaceVariantRow(.subtleStrong, label: ".subtleStrong")
                surfaceVariantRow(.accent, label: ".accent")
                surfaceVariantRow(.outlined, label: ".outlined")
            }
        }
    }

    private var modifierSection: some View {
        section(title: "Modifiers in use") {
            HStack(spacing: JinSpacing.small) {
                Text("jinTagStyle").jinTagStyle()
                Text("Foreground").jinTagStyle(foreground: .primary)
                Text("Tinted").jinTagStyle(foreground: .blue)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            content()
        }
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        HStack(spacing: JinSpacing.medium) {
            RoundedRectangle(cornerRadius: JinRadius.small)
                .fill(color)
                .frame(width: 72, height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: JinRadius.small)
                        .stroke(JinSemanticColor.borderSubtle, lineWidth: JinStrokeWidth.hairline)
                )
            Text(name).font(.system(.body, design: .monospaced))
            Spacer()
        }
    }

    private func borderSwatch(_ name: String, _ color: Color) -> some View {
        HStack(spacing: JinSpacing.medium) {
            RoundedRectangle(cornerRadius: JinRadius.small)
                .stroke(color, lineWidth: JinStrokeWidth.regular)
                .frame(width: 72, height: 32)
            Text(name).font(.system(.body, design: .monospaced))
            Spacer()
        }
    }

    private func shadowSwatch(_ name: String, _ color: Color, radius: CGFloat) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: JinRadius.medium)
                .fill(JinSemanticColor.raisedSurface)
                .frame(width: 96, height: 56)
                .shadow(color: color, radius: radius, x: 0, y: 2)
            Text(name)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(JinSpacing.small)
    }

    private func surfaceVariantRow(_ variant: JinSurfaceVariant, label: String) -> some View {
        Text(label)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, JinSpacing.medium)
            .padding(.vertical, JinSpacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .jinSurface(variant, cornerRadius: JinRadius.small)
    }
}

#Preview("Light") {
    JinDesignSystemPreview()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    JinDesignSystemPreview()
        .preferredColorScheme(.dark)
}
#endif
