import SwiftUI

struct AppearanceModePicker: View {
    @Binding var selection: AppAppearanceMode

    var body: some View {
        HStack(spacing: 18) {
            ForEach(AppAppearanceMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    VStack(spacing: 7) {
                        preview(mode)
                            .frame(width: 106, height: 66)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(
                                        selection == mode ? Color.accentColor : JinSemanticColor.borderEmphasized,
                                        lineWidth: selection == mode ? 2 : 0.5)
                            }
                            .accessibilityHidden(true)
                        Text(mode.label)
                            .font(.callout)
                            .foregroundStyle(.primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.label)
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Appearance")
    }

    private func preview(_ mode: AppAppearanceMode) -> some View {
        GeometryReader { proxy in
            miniature(dark: mode == .dark)
                .overlay(alignment: .trailing) {
                    if mode == .system {
                        miniature(dark: true)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .mask(alignment: .trailing) {
                                Rectangle().frame(width: proxy.size.width / 2)
                            }
                    }
                }
        }
    }

    private func miniature(dark: Bool) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 3) {
                    ForEach(0..<3) { _ in
                        Circle().fill(dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2)).frame(
                            width: 3, height: 3)
                    }
                }
                .padding(.bottom, 5)
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.4)).frame(height: 5)
                ForEach(0..<2) { _ in
                    RoundedRectangle(cornerRadius: 2).fill(dark ? Color.white.opacity(0.12) : Color.black.opacity(0.1))
                        .frame(height: 4)
                }
                Spacer(minLength: 0)
            }
            .padding(7)
            .frame(width: 35)
            .background(dark ? Color(white: 0.18) : Color(white: 0.9))
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 2).fill(dark ? Color.white.opacity(0.7) : Color.black.opacity(0.55))
                    .frame(width: 31, height: 4)
                ForEach(0..<2) { _ in
                    RoundedRectangle(cornerRadius: 2).fill(dark ? Color.white.opacity(0.2) : Color.black.opacity(0.16))
                        .frame(height: 3)
                }
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 3).fill(dark ? Color.white.opacity(0.09) : Color.black.opacity(0.06))
                    .frame(height: 12)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(dark ? Color(white: 0.1) : Color.white)
        }
    }
}
