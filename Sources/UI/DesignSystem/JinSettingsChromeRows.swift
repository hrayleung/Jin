import SwiftUI

/// Settings text field that keeps keystrokes local while the user is editing.
///
/// Binding writes (and any parent re-render / SwiftData save they trigger) are
/// debounced until typing pauses, focus leaves, or the view disappears. That
/// preserves macOS key-repeat (hold Delete/Backspace) which SwiftUI otherwise
/// interrupts when the external binding rewrites the field every character.
struct JinSettingsTextField: View {
    let title: String
    @Binding var text: String
    var usesMonospacedFont = false

    @State private var draft = ""
    @State private var lastPushedValue: String?
    @State private var pushTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

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
            .focused($isFocused)
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
                schedulePush(newValue)
            }
            .onChange(of: text) { _, newValue in
                // External updates (Reset, provider switch, AppStorage reload).
                // Ignore echoes of our own debounced pushes.
                guard newValue != lastPushedValue else { return }
                lastPushedValue = newValue
                draft = newValue
                pushTask?.cancel()
                pushTask = nil
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    flushPush()
                }
            }
            .onDisappear {
                flushPush()
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

    private func schedulePush(_ value: String) {
        pushTask?.cancel()
        pushTask = PluginAutosave.schedule {
            pushToExternal(value)
        }
    }

    private func flushPush() {
        pushTask?.cancel()
        pushTask = nil
        pushToExternal(draft)
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
        // `draft` as what the user typed until focus ends or an external edit.
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
            textField
        }
    }

    @ViewBuilder
    private var textField: some View {
        JinSettingsTextField(
            fieldTitle,
            text: $text,
            usesMonospacedFont: usesMonospacedFont
        )
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
        JinSettingsControlRow(title, supportingText: supportingText) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct JinSettingsMenuPicker<SelectionValue: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: SelectionValue
    let maxWidth: CGFloat
    let alignment: Alignment
    private let content: () -> Content

    init(
        _ title: String,
        selection: Binding<SelectionValue>,
        maxWidth: CGFloat = .infinity,
        alignment: Alignment = .leading,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        _selection = selection
        self.maxWidth = maxWidth
        self.alignment = alignment
        self.content = content
    }

    var body: some View {
        Picker(title, selection: $selection) {
            content()
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: maxWidth, alignment: alignment)
    }
}

struct JinSettingsSegmentedPicker<SelectionValue: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: SelectionValue
    let maxWidth: CGFloat
    private let content: () -> Content

    init(
        _ title: String,
        selection: Binding<SelectionValue>,
        maxWidth: CGFloat = .infinity,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        _selection = selection
        self.maxWidth = maxWidth
        self.content = content
    }

    var body: some View {
        Picker(title, selection: $selection) {
            content()
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(maxWidth: maxWidth)
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
        JinSettingsControlRow(title, supportingText: supportingText) {
            JinSettingsMenuPicker(title, selection: $selection, maxWidth: .infinity, alignment: .leading) {
                content()
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
        JinSettingsControlRow(title, labelWidth: labelWidth) {
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
