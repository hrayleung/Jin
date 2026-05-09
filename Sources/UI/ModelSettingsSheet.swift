import SwiftUI

struct ModelSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let model: ModelInfo
    let providerType: ProviderType?
    let onSave: (ModelInfo) -> Void

    @State private var modelType: ModelType
    @State private var contextWindowText: String
    @State private var maxOutputTokensText: String
    @State private var capabilities: ModelCapability
    @State private var reasoningEnabled: Bool
    @State private var reasoningType: ReasoningConfigType
    @State private var reasoningEffort: ReasoningEffort
    @State private var reasoningBudgetText: String
    @State private var reasoningCanDisable: Bool
    @State private var webSearchSupported: Bool
    @State private var validationError: String?

    init(
        model: ModelInfo,
        providerType: ProviderType?,
        onSave: @escaping (ModelInfo) -> Void
    ) {
        self.model = model
        self.providerType = providerType
        self.onSave = onSave

        let resolved = ModelSettingsResolver.resolve(model: model, providerType: providerType)
        let resolvedReasoning = resolved.reasoningConfig
        let initialEffort = resolvedReasoning?.defaultEffort ?? .medium
        let normalizedInitialEffort = ModelCapabilityRegistry.normalizedReasoningEffort(
            initialEffort,
            for: providerType,
            modelID: model.id
        )

        _modelType = State(initialValue: resolved.modelType)
        _contextWindowText = State(initialValue: "\(resolved.contextWindow)")
        _maxOutputTokensText = State(initialValue: model.overrides?.maxOutputTokens.map(String.init) ?? "")
        _capabilities = State(initialValue: resolved.capabilities)
        _reasoningEnabled = State(initialValue: resolvedReasoning?.type != ReasoningConfigType.none && resolvedReasoning != nil)
        _reasoningType = State(initialValue: resolvedReasoning?.type ?? .effort)
        _reasoningEffort = State(initialValue: normalizedInitialEffort)
        _reasoningBudgetText = State(initialValue: resolvedReasoning?.defaultBudget.map(String.init) ?? "")
        _reasoningCanDisable = State(initialValue: resolved.reasoningCanDisable)
        _webSearchSupported = State(initialValue: resolved.supportsWebSearch)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JinSpacing.large) {
                    headerCard
                    typeCard
                    tokenLimitsCard
                    capabilitiesCard
                    reasoningCard
                    if let validationError {
                        errorBanner(validationError)
                    }
                }
                .padding(JinSpacing.xLarge)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background {
                LinearGradient(
                    colors: [
                        JinSemanticColor.detailSurface,
                        JinSemanticColor.surface.opacity(0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .navigationTitle("Model Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                if model.overrides != nil {
                    ToolbarItem(placement: .automatic) {
                        Button("Reset", role: .destructive) {
                            resetOverrides()
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 580, minHeight: 620)
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack(alignment: .center, spacing: JinSpacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                    .fill(JinSemanticColor.accentSurface)
                Image(systemName: ModelTypeIconography.glyph(for: modelType))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 44, height: 44)
            .animation(.easeInOut(duration: 0.2), value: modelType)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: JinSpacing.xSmall) {
                    Text(model.id)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let providerName = providerType?.displayName {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(providerName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: JinSpacing.small)

            if model.overrides != nil {
                Text("Customized")
                    .jinTagStyle(foreground: .accentColor)
            }
        }
        .padding(JinSpacing.large)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    // MARK: - Type

    private var typeCard: some View {
        sectionCard(title: "Type", subtitle: "How this model is used in conversations.") {
            HStack(spacing: JinSpacing.small) {
                ForEach(ModelType.allCases, id: \.self) { type in
                    typeChip(type)
                }
            }
        }
    }

    private func typeChip(_ type: ModelType) -> some View {
        let isSelected = modelType == type
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                modelType = type
            }
        } label: {
            HStack(spacing: JinSpacing.xSmall) {
                Image(systemName: ModelTypeIconography.glyph(for: type))
                    .font(.system(size: 13, weight: .semibold))
                Text(type.displayName)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .padding(.horizontal, JinSpacing.medium)
            .padding(.vertical, JinSpacing.small + 1)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                .fill(isSelected ? JinSemanticColor.accentSurface : JinSemanticColor.subtleSurface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.32) : Color.clear,
                    lineWidth: JinStrokeWidth.regular
                )
        }
    }

    // MARK: - Token Limits

    private var tokenLimitsCard: some View {
        sectionCard(title: "Token Limits", subtitle: "Constraints on input window and reply length.") {
            HStack(alignment: .top, spacing: JinSpacing.medium) {
                numberField(
                    title: "Context length",
                    helper: "Required",
                    prompt: "200000",
                    text: $contextWindowText
                )
                numberField(
                    title: "Max output",
                    helper: "Optional · provider default if blank",
                    prompt: "Auto",
                    text: $maxOutputTokensText
                )
            }
        }
    }

    private func numberField(
        title: String,
        helper: String,
        prompt: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)

            TextField(text: text, prompt: Text(prompt)) { EmptyView() }
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.plain)
                .padding(.horizontal, JinSpacing.medium)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                        .fill(JinSemanticColor.textSurface)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                        .stroke(JinSemanticColor.separator.opacity(0.55), lineWidth: JinStrokeWidth.hairline)
                }

            Text(helper)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Capabilities

    private var capabilitiesCard: some View {
        sectionCard(title: "Capabilities", subtitle: "What this model can read or produce.") {
            let columns = [
                GridItem(.flexible(), spacing: JinSpacing.small),
                GridItem(.flexible(), spacing: JinSpacing.small)
            ]
            LazyVGrid(columns: columns, spacing: JinSpacing.small) {
                capabilityTile(title: "Web Search", icon: "globe", isOn: $webSearchSupported)
                capabilityTile(title: "Image input", icon: "photo", isOn: capabilityBinding(.vision))
                capabilityTile(title: "Image output", icon: "sparkles", isOn: capabilityBinding(.imageGeneration))
                capabilityTile(title: "Audio input", icon: "waveform", isOn: capabilityBinding(.audio))
                capabilityTile(title: "Video input", icon: "video", isOn: capabilityBinding(.videoInput))
                capabilityTile(title: "Video generation", icon: "film", isOn: capabilityBinding(.videoGeneration))
            }
        }
    }

    private func capabilityTile(title: String, icon: String, isOn: Binding<Bool>) -> some View {
        let on = isOn.wrappedValue
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: JinSpacing.medium) {
                ZStack {
                    Circle()
                        .fill(on ? Color.accentColor.opacity(0.18) : JinSemanticColor.subtleSurfaceStrong)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(on ? Color.accentColor : Color.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .frame(width: 28, height: 28)

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: JinSpacing.xSmall)

                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(on ? Color.accentColor : Color.secondary.opacity(0.45))
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(.horizontal, JinSpacing.medium)
            .padding(.vertical, JinSpacing.small + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                .fill(on ? JinSemanticColor.accentSurface : JinSemanticColor.subtleSurface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                .stroke(
                    on ? Color.accentColor.opacity(0.32) : JinSemanticColor.separator.opacity(0.4),
                    lineWidth: JinStrokeWidth.hairline
                )
        }
    }

    private func capabilityBinding(_ capability: ModelCapability) -> Binding<Bool> {
        Binding(
            get: { capabilities.contains(capability) },
            set: { newValue in
                if newValue {
                    capabilities.insert(capability)
                } else {
                    capabilities.remove(capability)
                }
            }
        )
    }

    // MARK: - Reasoning

    private var reasoningCard: some View {
        JinSettingsCard(spacing: JinSpacing.medium) {
            HStack(alignment: .firstTextBaseline, spacing: JinSpacing.medium) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reasoning")
                        .font(.headline)
                    Text("Allow this model to output thinking before responding.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: JinSpacing.small)

                Toggle("", isOn: $reasoningEnabled.animation(.easeInOut(duration: 0.2)))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Reasoning")
            }

            if reasoningEnabled {
                Rectangle()
                    .fill(JinSemanticColor.separator.opacity(0.6))
                    .frame(height: JinStrokeWidth.hairline)

                reasoningModePicker

                if reasoningType == .effort {
                    reasoningEffortPicker
                } else if reasoningType == .budget {
                    reasoningBudgetField
                }

                inlineToggleRow(title: "Allow disabling per chat", isOn: $reasoningCanDisable)
            }
        }
    }

    private var reasoningModePicker: some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Text("Mode")
                .font(.subheadline.weight(.medium))

            HStack(spacing: JinSpacing.xSmall) {
                reasoningModeChip("Effort", type: .effort)
                reasoningModeChip("Budget", type: .budget)
                reasoningModeChip("Toggle only", type: .toggle)
            }
        }
    }

    private func reasoningModeChip(_ title: String, type: ReasoningConfigType) -> some View {
        let isSelected = reasoningType == type
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                reasoningType = type
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .padding(.horizontal, JinSpacing.medium)
                .padding(.vertical, JinSpacing.small)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                .fill(isSelected ? JinSemanticColor.accentSurface : JinSemanticColor.subtleSurface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.32) : Color.clear,
                    lineWidth: JinStrokeWidth.regular
                )
        }
    }

    private var reasoningEffortPicker: some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Text("Default effort")
                .font(.subheadline.weight(.medium))

            ModelSettingsFlowLayout(spacing: JinSpacing.xSmall) {
                ForEach(availableReasoningEffortLevels, id: \.self) { effort in
                    effortPill(effort)
                }
            }
        }
    }

    private func effortPill(_ effort: ReasoningEffort) -> some View {
        let isSelected = reasoningEffort == effort
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                reasoningEffort = effort
            }
        } label: {
            Text(effort.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .padding(.horizontal, JinSpacing.medium - 1)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            Capsule(style: .continuous)
                .fill(isSelected ? JinSemanticColor.accentSurface : JinSemanticColor.subtleSurface)
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.32) : JinSemanticColor.separator.opacity(0.35),
                    lineWidth: JinStrokeWidth.hairline
                )
        }
    }

    private var reasoningBudgetField: some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Text("Default budget tokens")
                .font(.subheadline.weight(.medium))

            TextField(text: $reasoningBudgetText, prompt: Text("e.g. 1024")) { EmptyView() }
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.plain)
                .padding(.horizontal, JinSpacing.medium)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                        .fill(JinSemanticColor.textSurface)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                        .stroke(JinSemanticColor.separator.opacity(0.55), lineWidth: JinStrokeWidth.hairline)
                }
        }
    }

    private func inlineToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: JinSpacing.small) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer(minLength: JinSpacing.small)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(title)
        }
    }

    // MARK: - Section helper

    private func sectionCard<Inner: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Inner
    ) -> some View {
        JinSettingsCard(spacing: JinSpacing.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content()
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: JinSpacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 2)

            Text(message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.red)
        .padding(JinSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                .fill(Color.red.opacity(0.1))
        }
        .overlay {
            RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                .stroke(Color.red.opacity(0.25), lineWidth: JinStrokeWidth.hairline)
        }
    }

    // MARK: - Helpers

    private var availableReasoningEffortLevels: [ReasoningEffort] {
        ModelCapabilityRegistry.supportedReasoningEfforts(
            for: providerType,
            modelID: model.id
        )
    }

    private func resetOverrides() {
        onSave(
            ModelInfo(
                id: model.id,
                name: model.name,
                capabilities: model.capabilities,
                contextWindow: model.contextWindow,
                maxOutputTokens: model.maxOutputTokens,
                reasoningConfig: model.reasoningConfig,
                overrides: nil,
                catalogMetadata: model.catalogMetadata,
                isEnabled: model.isEnabled
            )
        )
        dismiss()
    }

    private func save() {
        guard let contextWindow = ModelSettingsSheetSupport.positiveInteger(from: contextWindowText) else {
            validationError = "Context length must be a positive integer."
            return
        }

        let maxOutputTokens: Int?
        switch ModelSettingsSheetSupport.optionalPositiveInteger(from: maxOutputTokensText) {
        case .empty:
            maxOutputTokens = nil
        case .value(let value):
            maxOutputTokens = value
        case .invalid:
            validationError = "Max output must be a positive integer."
            return
        }

        var updatedCapabilities = capabilities
        if reasoningEnabled {
            updatedCapabilities.insert(.reasoning)
        } else {
            updatedCapabilities.remove(.reasoning)
        }

        switch modelType {
        case .chat:
            break
        case .image:
            updatedCapabilities.insert(.imageGeneration)
            updatedCapabilities.remove(.videoGeneration)
        case .video:
            updatedCapabilities.insert(.videoGeneration)
            updatedCapabilities.remove(.imageGeneration)
        }

        let reasoningConfig: ModelReasoningConfig?
        if reasoningEnabled {
            switch reasoningType {
            case .effort:
                let normalizedEffort = ModelCapabilityRegistry.normalizedReasoningEffort(
                    reasoningEffort,
                    for: providerType,
                    modelID: model.id
                )
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: normalizedEffort)
            case .budget:
                guard let budget = ModelSettingsSheetSupport.positiveInteger(from: reasoningBudgetText) else {
                    validationError = "Reasoning budget must be a positive integer."
                    return
                }
                reasoningConfig = ModelReasoningConfig(type: .budget, defaultBudget: budget)
            case .toggle:
                reasoningConfig = ModelReasoningConfig(type: .toggle)
            case .none:
                reasoningConfig = nil
            }
        } else {
            // Explicitly persist "off" when the base model declares reasoning support.
            // Otherwise a nil override falls back to the base reasoning config on reload.
            if model.reasoningConfig != nil {
                reasoningConfig = ModelReasoningConfig(type: .none)
            } else {
                reasoningConfig = nil
            }
        }

        let baseModelType = ModelSettingsResolver.inferModelType(
            capabilities: model.capabilities,
            modelID: model.id
        )
        let baseReasoningCanDisable = ModelSettingsResolver.defaultReasoningCanDisable(
            for: providerType,
            modelID: model.id
        )
        let baseWebSearchSupported = ModelCapabilityRegistry.supportsWebSearch(
            for: providerType,
            modelID: model.id
        )
        let baseMaxOutputTokens = providerType.flatMap {
            ModelCatalog.entry(for: model.id, provider: $0)?.maxOutputTokens
        }

        var overrides = ModelOverrides()
        if modelType != baseModelType {
            overrides.modelType = modelType
        }
        if contextWindow != model.contextWindow {
            overrides.contextWindow = contextWindow
        }
        if let maxOutputTokens, maxOutputTokens != baseMaxOutputTokens {
            overrides.maxOutputTokens = maxOutputTokens
        }
        if updatedCapabilities != model.capabilities {
            overrides.capabilities = updatedCapabilities
        }
        if reasoningConfig != model.reasoningConfig {
            overrides.reasoningConfig = reasoningConfig
        }
        if reasoningCanDisable != baseReasoningCanDisable {
            overrides.reasoningCanDisable = reasoningCanDisable
        }
        if webSearchSupported != baseWebSearchSupported {
            overrides.webSearchSupported = webSearchSupported
        }

        let finalOverrides: ModelOverrides? = overrides.isEmpty ? nil : overrides
        onSave(
            ModelInfo(
                id: model.id,
                name: model.name,
                capabilities: model.capabilities,
                contextWindow: model.contextWindow,
                maxOutputTokens: model.maxOutputTokens,
                reasoningConfig: model.reasoningConfig,
                overrides: finalOverrides,
                catalogMetadata: model.catalogMetadata,
                isEnabled: model.isEnabled
            )
        )
        dismiss()
    }
}

// MARK: - Local helpers

private enum ModelTypeIconography {
    static func glyph(for type: ModelType) -> String {
        switch type {
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .image: return "photo.fill"
        case .video: return "film.fill"
        }
    }
}

private struct ModelSettingsFlowLayout: Layout {
    var spacing: CGFloat = JinSpacing.xSmall

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return layout(sizes: sizes, containerWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let offsets = layout(sizes: sizes, containerWidth: bounds.width).offsets

        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + offsets[index].x, y: bounds.minY + offsets[index].y),
                proposal: .unspecified
            )
        }
    }

    private func layout(sizes: [CGSize], containerWidth: CGFloat) -> (offsets: [CGPoint], size: CGSize) {
        var offsets: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for size in sizes {
            if x + size.width > containerWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            offsets.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x)
        }

        return (offsets, CGSize(width: maxWidth, height: y + rowHeight))
    }
}
