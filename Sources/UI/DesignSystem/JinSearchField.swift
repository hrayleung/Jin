import SwiftUI

/// A search field with an inset well for sidebars or borderless popover chrome.
/// The containing window supplies the material in both cases.
struct JinSearchField: View {
    enum Chrome {
        case inset
        case borderless
    }

    @Binding var text: String
    let prompt: String
    var focus: FocusState<Bool>.Binding?
    var focusesOnAppear = false
    var chrome: Chrome = .inset

    @FocusState private var localFocus: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    private var fieldFocus: FocusState<Bool>.Binding { focus ?? $localFocus }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 14)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("", text: $text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .font(.body)
                .focused(fieldFocus)
                .accessibilityLabel(prompt)

            if !text.isEmpty {
                Button {
                    text = ""
                    fieldFocus.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .help("Clear search")
            }
        }
        .padding(.horizontal, chrome == .inset ? 9 : 0)
        .frame(minHeight: 30)
        .background {
            if chrome == .inset {
                RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                    .fill(JinSemanticColor.controlFill)
            }
        }
        .overlay {
            if chrome == .inset || contrast == .increased {
                RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                    .strokeBorder(
                        fieldFocus.wrappedValue
                            ? Color.accentColor.opacity(0.55)
                            : JinThemeResolver.borderHairline(contrast: contrast),
                        lineWidth: fieldFocus.wrappedValue || contrast == .increased ? 1 : JinStrokeWidth.hairline
                    )
                    .allowsHitTesting(false)
            }
        }
        .task {
            guard focusesOnAppear else { return }
            // Wait for the popover's window before handing off first responder.
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            fieldFocus.wrappedValue = true
        }
    }
}
