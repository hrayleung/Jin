import SwiftUI

/// Settings text field that keeps the visible string in a local draft.
///
/// The external binding is updated **synchronously** on every keystroke so
/// toolbar Save/Apply actions always read the latest value (debouncing here
/// would drop input when the user types and immediately confirms a sheet).
///
/// Isolation still preserves macOS key-repeat: transforming bindings (e.g. blank
/// base URL → default) must not rewrite the field mid-edit, which is what used
/// to interrupt hold-Delete. Echoes of our own pushes are ignored while true
/// external changes (Reset, provider switch) still replace the draft.
struct JinSettingsTextField: View {
    let title: String
    @Binding var text: String
    var usesMonospacedFont = false

    @State private var draft = ""
    @State private var lastPushedValue: String?

    init(
        _ title: String,
        text: Binding<String>,
        usesMonospacedFont: Bool = false
    ) {
        self.title = title
        _text = text
        self.usesMonospacedFont = usesMonospacedFont
    }

    var body: some View {
        styledField
            .onAppear {
                // Seed once per appear; identity changes (e.g. switching provider)
                // recreate the view and re-run this.
                if lastPushedValue == nil {
                    draft = text
                    lastPushedValue = text
                }
            }
            .onChange(of: draft) { _, newValue in
                guard newValue != lastPushedValue else { return }
                pushToExternal(newValue)
            }
            .onChange(of: text) { _, newValue in
                // External updates (Reset, provider switch, AppStorage reload).
                // Ignore echoes of our own pushes so transforming bindings cannot
                // bounce the caret / kill key-repeat mid-edit.
                guard newValue != lastPushedValue else { return }
                lastPushedValue = newValue
                draft = newValue
            }
    }

    @ViewBuilder
    private var styledField: some View {
        if usesMonospacedFont {
            baseTextField
                .font(.system(.body, design: .monospaced))
        } else {
            baseTextField
        }
    }

    private var baseTextField: some View {
        TextField(title, text: $draft)
            .textFieldStyle(.roundedBorder)
    }

    private func pushToExternal(_ value: String) {
        // Record the intended value first so transforming bindings (e.g. blank
        // base URL → default) don't bounce the draft while the user is mid-edit.
        lastPushedValue = value
        if text != value {
            text = value
        }
        // If the binding rewrites the stored value (normalize / default fill),
        // remember the resolved value so the onChange echo is ignored, but keep
        // `draft` as what the user typed until an external edit arrives.
        let resolved = text
        if resolved != value {
            lastPushedValue = resolved
        }
    }
}

struct JinSettingsTextFieldRow: View {
    let title: String
    let fieldTitle: String
    let supportingText: String?
    let usesMonospacedFont: Bool
    @Binding var text: String

    init(
        _ title: String,
        fieldTitle: String? = nil,
        supportingText: String? = nil,
        text: Binding<String>,
        usesMonospacedFont: Bool = false
    ) {
        self.title = title
        self.fieldTitle = fieldTitle ?? title
        self.supportingText = supportingText
        _text = text
        self.usesMonospacedFont = usesMonospacedFont
    }

    var body: some View {
        JinSettingsControlRow(title, supportingText: supportingText) {
            JinSettingsTextField(
                fieldTitle,
                text: $text,
                usesMonospacedFont: usesMonospacedFont
            )
        }
    }
}

struct JinSettingsTextEditor: View {
    let placeholder: String?
    @Binding var text: String
    var minHeight: CGFloat = 84
    var usesMonospacedFont = true
    var cornerRadius = JinRadius.small
    var placeholderLeadingPadding: CGFloat = 5

    init(
        text: Binding<String>,
        placeholder: String? = nil,
        minHeight: CGFloat = 84,
        usesMonospacedFont: Bool = true,
        cornerRadius: CGFloat = JinRadius.small,
        placeholderLeadingPadding: CGFloat = 5
    ) {
        _text = text
        self.placeholder = placeholder
        self.minHeight = minHeight
        self.usesMonospacedFont = usesMonospacedFont
        self.cornerRadius = cornerRadius
        self.placeholderLeadingPadding = placeholderLeadingPadding
    }

    var body: some View {
        textEditor
            .frame(minHeight: minHeight)
            .jinTextEditorField(cornerRadius: cornerRadius)
            .overlay(alignment: .topLeading) {
                placeholderView
            }
    }

    @ViewBuilder
    private var textEditor: some View {
        if usesMonospacedFont {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
        } else {
            TextEditor(text: $text)
        }
    }

    @ViewBuilder
    private var placeholderView: some View {
        if let placeholder, text.isEmpty {
            Text(placeholder)
                .foregroundColor(.secondary)
                .padding(.top, 8)
                .padding(.leading, placeholderLeadingPadding)
                .allowsHitTesting(false)
        }
    }
}

struct JinSettingsSecureFieldRow: View {
    let title: String
    let fieldTitle: String
    let supportingText: String?
    @Binding var text: String
    @Binding var isRevealed: Bool
    var usesMonospacedFont = false
    var revealHelp = "Show value"
    var concealHelp = "Hide value"

    init(
        _ title: String,
        fieldTitle: String? = nil,
        supportingText: String? = nil,
        text: Binding<String>,
        isRevealed: Binding<Bool>,
        usesMonospacedFont: Bool = false,
        revealHelp: String = "Show value",
        concealHelp: String = "Hide value"
    ) {
        self.title = title
        self.fieldTitle = fieldTitle ?? title
        self.supportingText = supportingText
        _text = text
        _isRevealed = isRevealed
        self.usesMonospacedFont = usesMonospacedFont
        self.revealHelp = revealHelp
        self.concealHelp = concealHelp
    }

    var body: some View {
        JinSettingsControlRow(title, supportingText: supportingText) {
            JinRevealableSecureField(
                title: fieldTitle,
                text: $text,
                isRevealed: $isRevealed,
                usesMonospacedFont: usesMonospacedFont,
                revealHelp: revealHelp,
                concealHelp: concealHelp
            )
        }
    }
}

struct JinSettingsToggleRow: View {
    let title: String
    let supportingText: String?
    @Binding var isOn: Bool

    init(
        _ title: String,
        supportingText: String? = nil,
        isOn: Binding<Bool>
    ) {
        self.title = title
        self.supportingText = supportingText
        _isOn = isOn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Toggle(title, isOn: $isOn)
            if let supportingText, !supportingText.isEmpty {
                Text(supportingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct JinSettingsMenuPicker<SelectionValue: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: SelectionValue
    private let content: () -> Content

    init(
        _ title: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        _selection = selection
        self.content = content
    }

    var body: some View {
        Picker(title, selection: $selection) {
            content()
        }
    }
}

struct JinSettingsSegmentedPicker<SelectionValue: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: SelectionValue
    private let content: () -> Content

    init(
        _ title: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        _selection = selection
        self.content = content
    }

    var body: some View {
        Picker(title, selection: $selection) {
            content()
        }
        .pickerStyle(.segmented)
    }
}

struct JinSettingsPickerRow<SelectionValue: Hashable, Content: View>: View {
    let title: String
    let supportingText: String?
    @Binding var selection: SelectionValue
    private let content: () -> Content

    init(
        _ title: String,
        supportingText: String? = nil,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.supportingText = supportingText
        _selection = selection
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Picker(title, selection: $selection) {
                content()
            }
            if let supportingText, !supportingText.isEmpty {
                Text(supportingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct JinSettingsSliderValueRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Pass `nil` for a continuous slider. AppKit draws a tick mark per step, so
    /// a fine step over a wide range renders a dotted track; quantize in the
    /// binding instead when the value should still snap.
    var step: Double? = nil
    var valueWidth: CGFloat = 52
    var labelWidth: CGFloat = 156

    var body: some View {
        JinSettingsControlRow(title) {
            HStack {
                slider
                Text(value.formatted(.number.precision(.fractionLength(2))))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: valueWidth, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private var slider: some View {
        if let step {
            Slider(value: $value, in: range, step: step)
        } else {
            Slider(value: $value, in: range)
        }
    }
}
