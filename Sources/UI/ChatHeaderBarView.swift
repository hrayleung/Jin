import SwiftUI

struct ChatHeaderToolbarThread: Identifiable {
    let id: UUID
    let providerIconID: String?
    let title: String
    let isSelected: Bool
    let isActive: Bool
    let isRemovable: Bool
}

private struct ChatHeaderLeadingSymbol: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: JinControlMetrics.iconButtonGlyphSize, weight: .semibold))
            .imageScale(.medium)
            .foregroundStyle(.secondary)
            // These two SF Symbols do not share the same optical center at toolbar size.
            // Keep the correction local to this header instead of pushing a generic icon rule.
            .offset(y: visualVerticalOffset)
    }

    private var visualVerticalOffset: CGFloat {
        switch systemName {
        case "square.and.pencil":
            return -0.95
        case "sidebar.leading":
            return 0
        default:
            return 0
        }
    }
}

struct ChatHeaderBarView<ModelPickerContent: View, AddModelPickerContent: View>: View {
    let isSidebarHidden: Bool
    let onToggleSidebar: (() -> Void)?
    let onNewChat: (() -> Void)?
    let currentProviderIconID: String?
    let currentModelName: String
    let toolbarThreads: [ChatHeaderToolbarThread]
    @Binding var isModelPickerPresented: Bool
    @Binding var isAddModelPickerPresented: Bool
    let isStarred: Bool
    let starShortcutLabel: String?
    let addModelShortcutLabel: String?
    let onToggleStar: () -> Void
    let onOpenAssistantInspector: () -> Void
    let onRequestDeleteConversation: () -> Void
    let onToggleToolbarThread: (UUID) -> Void
    let onActivateToolbarThread: (UUID) -> Void
    let onRemoveToolbarThread: (UUID) -> Void
    private let modelPickerPopover: () -> ModelPickerContent
    private let addModelPopover: () -> AddModelPickerContent

    init(
        isSidebarHidden: Bool,
        onToggleSidebar: (() -> Void)?,
        onNewChat: (() -> Void)? = nil,
        currentProviderIconID: String?,
        currentModelName: String,
        toolbarThreads: [ChatHeaderToolbarThread],
        isModelPickerPresented: Binding<Bool>,
        isAddModelPickerPresented: Binding<Bool>,
        isStarred: Bool,
        starShortcutLabel: String? = nil,
        addModelShortcutLabel: String? = nil,
        onToggleStar: @escaping () -> Void,
        onOpenAssistantInspector: @escaping () -> Void,
        onRequestDeleteConversation: @escaping () -> Void,
        onToggleToolbarThread: @escaping (UUID) -> Void,
        onActivateToolbarThread: @escaping (UUID) -> Void,
        onRemoveToolbarThread: @escaping (UUID) -> Void,
        @ViewBuilder modelPickerPopover: @escaping () -> ModelPickerContent,
        @ViewBuilder addModelPopover: @escaping () -> AddModelPickerContent
    ) {
        self.isSidebarHidden = isSidebarHidden
        self.onToggleSidebar = onToggleSidebar
        self.onNewChat = onNewChat
        self.currentProviderIconID = currentProviderIconID
        self.currentModelName = currentModelName
        self.toolbarThreads = toolbarThreads
        _isModelPickerPresented = isModelPickerPresented
        _isAddModelPickerPresented = isAddModelPickerPresented
        self.isStarred = isStarred
        self.starShortcutLabel = starShortcutLabel
        self.addModelShortcutLabel = addModelShortcutLabel
        self.onToggleStar = onToggleStar
        self.onOpenAssistantInspector = onOpenAssistantInspector
        self.onRequestDeleteConversation = onRequestDeleteConversation
        self.onToggleToolbarThread = onToggleToolbarThread
        self.onActivateToolbarThread = onActivateToolbarThread
        self.onRemoveToolbarThread = onRemoveToolbarThread
        self.modelPickerPopover = modelPickerPopover
        self.addModelPopover = addModelPopover
    }

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            sidebarButton
            modelPickerButton
            toolbarArea
            addModelButton
            headerActions
        }
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, JinSpacing.small)
        .frame(minHeight: 38)
        .background(JinSemanticColor.detailSurface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(JinSemanticColor.separator.opacity(0.45))
                .frame(height: JinStrokeWidth.hairline)
        }
    }

    @ViewBuilder
    private var sidebarButton: some View {
        if isSidebarHidden, let onToggleSidebar {
            headerIconButton(
                systemName: "sidebar.leading",
                helpText: "Show Sidebar",
                action: onToggleSidebar
            )

            if let onNewChat {
                headerIconButton(
                    systemName: "square.and.pencil",
                    helpText: "New Chat",
                    action: onNewChat
                )
            }
        }
    }

    private func headerIconButton(systemName: String, helpText: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ChatHeaderLeadingSymbol(systemName: systemName)
        }
        .buttonStyle(JinIconButtonStyle(showBackground: false))
        .help(helpText)
    }

    private var modelPickerButton: some View {
        Button {
            isModelPickerPresented = true
        } label: {
            HStack(spacing: 6) {
                ProviderIconView(iconID: currentProviderIconID, size: 14)
                    .frame(width: 16, height: 16)

                Text(currentModelName)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help("Select model")
        .accessibilityLabel("Select model")
        .popover(isPresented: $isModelPickerPresented, arrowEdge: .bottom) {
            modelPickerPopover()
        }
    }

    @ViewBuilder
    private var toolbarArea: some View {
        if toolbarThreads.isEmpty {
            Spacer(minLength: 0)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(toolbarThreads) { thread in
                        HStack(spacing: 4) {
                            toolbarThreadToggle(thread)

                            if thread.isRemovable {
                                Button {
                                    onRemoveToolbarThread(thread.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove model from this chat")
                            }
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func toolbarThreadToggle(_ thread: ChatHeaderToolbarThread) -> some View {
        Button {
            onToggleToolbarThread(thread.id)
        } label: {
            HStack(spacing: 4) {
                ProviderIconView(iconID: thread.providerIconID, size: 10)
                    .frame(width: 10, height: 10)
                Text(thread.title)
                    .font(.caption2)
                    .lineLimit(1)
                Image(systemName: thread.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(thread.isSelected ? Color.accentColor : Color.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .circular)
                    .fill(thread.isSelected ? Color.accentColor.opacity(0.2) : JinSemanticColor.surface)
            )
            .overlay(
                Capsule(style: .circular)
                    .stroke(
                        thread.isActive ? Color.accentColor.opacity(0.75) : JinSemanticColor.separator.opacity(0.45),
                        lineWidth: thread.isActive ? JinStrokeWidth.emphasized : JinStrokeWidth.hairline
                    )
            )
        }
        .buttonStyle(.plain)
        .help(thread.isSelected ? "Selected for next send" : "Click to include this model")
        .contextMenu {
            Button("Set as input target") {
                onActivateToolbarThread(thread.id)
            }

            if thread.isRemovable {
                Divider()
                Button("Remove from this chat", role: .destructive) {
                    onRemoveToolbarThread(thread.id)
                }
            }
        }
    }

    private var addModelButton: some View {
        Button {
            isAddModelPickerPresented = true
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(addModelShortcutLabel.map { "Add model (\($0))" } ?? "Add model")
        .popover(isPresented: $isAddModelPickerPresented, arrowEdge: .bottom) {
            addModelPopover()
        }
    }

    private var headerActions: some View {
        HStack(spacing: JinSpacing.xSmall) {
            Button(action: onToggleStar) {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .font(.system(size: JinControlMetrics.iconButtonGlyphSize, weight: .semibold))
                    .foregroundStyle(isStarred ? Color.orange : Color.primary)
            }
            .buttonStyle(JinIconButtonStyle())
            .help({
                let base = isStarred ? "Unstar chat" : "Star chat"
                if let label = starShortcutLabel { return "\(base) (\(label))" }
                return base
            }())

            Button(action: onOpenAssistantInspector) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: JinControlMetrics.iconButtonGlyphSize, weight: .semibold))
            }
            .buttonStyle(JinIconButtonStyle())
            .help("Assistant Settings")

            Button(role: .destructive, action: onRequestDeleteConversation) {
                Image(systemName: "trash")
                    .font(.system(size: JinControlMetrics.iconButtonGlyphSize, weight: .semibold))
            }
            .buttonStyle(JinIconButtonStyle())
            .help("Delete chat")
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
