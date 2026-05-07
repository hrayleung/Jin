import SwiftUI

// MARK: - Floating Composer

extension ChatView {

    var floatingComposer: some View {
        GeometryReader { geometry in
            let layout = floatingComposerLayout(containerWidth: geometry.size.width)

            floatingComposerContent
                .frame(width: layout.visibleContainerWidth, height: geometry.size.height, alignment: .bottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .offset(x: layout.offset)
        }
        .allowsHitTesting(!isExpandedComposerPresented)
    }

    private var floatingComposerContent: some View {
        VStack(spacing: JinSpacing.small) {
            if isComposerHidden {
                CollapsedComposerBar(
                    hasContent: !messageText.isEmpty || !draftAttachments.isEmpty || !draftQuotes.isEmpty,
                    onExpand: showComposer
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                if isSlashMCPPopoverVisible, slashCommandTarget == .composer {
                    SlashCommandMCPPopover(
                        servers: slashCommandMCPItems,
                        filterText: slashMCPFilterText,
                        highlightedIndex: slashMCPHighlightedIndex,
                        onSelectServer: handleSlashCommandSelectServer,
                        onDismiss: dismissSlashCommandPopover
                    )
                    .padding(.horizontal, JinSpacing.medium)
                    .frame(maxWidth: ChatConversationLayoutMetrics.composerMaxWidth)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                composerOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .opacity(isExpandedComposerPresented ? 0 : 1)
        .animation(.easeInOut(duration: 0.24), value: mainSidebarWidth)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: isComposerHidden)
        .animation(.easeOut(duration: 0.15), value: isSlashMCPPopoverVisible)
        .animation(.easeOut(duration: 0.18), value: isExpandedComposerPresented)
        .padding(.horizontal, ChatConversationLayoutMetrics.compactHorizontalInset)
        .padding(.bottom, 16)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: ComposerHeightPreferenceKey.self, value: geo.size.height)
            }
        }
    }

    private func floatingComposerLayout(containerWidth: CGFloat) -> (
        visibleContainerWidth: CGFloat,
        contentWidth: CGFloat,
        offset: CGFloat
    ) {
        let visibleContainerWidth = ChatConversationLayoutMetrics.visibleContainerWidth(
            containerWidth: containerWidth,
            sidebarWidth: mainSidebarWidth,
            isSidebarHidden: isSidebarHidden
        )
        let contentWidth = min(
            ChatConversationLayoutMetrics.composerMaxWidth,
            max(0, visibleContainerWidth - ChatConversationLayoutMetrics.compactHorizontalInset * 2)
        )
        let offset = ChatConversationLayoutMetrics.sidebarCompensationOffset(
            sidebarWidth: mainSidebarWidth,
            isSidebarHidden: isSidebarHidden,
            compensationRatio: sidebarCompensationRatio
        )
        return (visibleContainerWidth, contentWidth, offset)
    }

    func showComposer() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            isComposerHidden = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isComposerFocused = true
        }
    }

    func toggleComposerVisibility() {
        if isComposerHidden {
            showComposer()
        } else {
            isComposerFocused = false
            if isExpandedComposerPresented {
                isExpandedComposerPresented = false
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                isComposerHidden = true
            }
        }
    }
}
