import SwiftUI

/// Compact stacked deck for many user-message images, unfolding into a wrap
/// grid. Height uses the shared disclosure curve so NSTableView row measure
/// does not jitter.
struct UserMessageImageStackView: View {
    let imageParts: [RenderedContentPart]
    let deferCodeHighlightUpgrade: Bool
    let payloadResolver: RenderedMessagePayloadResolver
    var onExpansionChanged: () -> Void = {}

    @State private var isExpanded = false
    @State private var hasEverExpanded = false

    var body: some View {
        if UserMessageImageStackSupport.shouldStack(imageCount: imageParts.count) {
            stackedBody
        } else {
            inlineRow
        }
    }

    private var inlineRow: some View {
        HStack(spacing: UserMessageImageStackSupport.thumbnailSpacing) {
            ForEach(Array(imageParts.enumerated()), id: \.offset) { _, part in
                imageThumb(part)
            }
        }
    }

    private var stackedBody: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            header
                .fixedSize()

            if hasEverExpanded {
                JinCollapsibleContent(isExpanded: isExpanded) {
                    expandedGrid
                }
                // Keep the grid out of collapsed layout. Otherwise LazyVGrid
                // still reports a full-bubble width at height 0 and the user
                // bubble cannot shrink back after Hide.
                .frame(maxWidth: isExpanded ? .infinity : 0, alignment: .topLeading)
                .clipped()
            }
        }
        .frame(maxWidth: isExpanded ? .infinity : nil, alignment: .leading)
        .fixedSize(horizontal: !isExpanded, vertical: false)
        .onChange(of: isExpanded) { _, _ in
            onExpansionChanged()
        }
    }

    private var header: some View {
        let stackSize = UserMessageImageStackSupport.collapsedStackSize(imageCount: imageParts.count)
        return Button(action: toggleExpanded) {
            VStack(alignment: .leading, spacing: JinSpacing.small) {
                collapsedFan
                    .frame(width: stackSize.width, height: stackSize.height, alignment: .topLeading)

                HStack(spacing: JinSpacing.xSmall) {
                    Text(UserMessageImageStackSupport.titleText(imageCount: imageParts.count))
                        .font(.caption)
                        .foregroundStyle(JinSemanticColor.textSecondary)
                    JinDisclosureChevron(isExpanded: isExpanded)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(UserMessageImageStackSupport.actionText(isExpanded: isExpanded))
        .accessibilityLabel(UserMessageImageStackSupport.titleText(imageCount: imageParts.count))
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isExpanded ? "Hides the image grid" : "Shows every image")
    }

    private var collapsedFan: some View {
        let visible = UserMessageImageStackSupport.previewCount(imageCount: imageParts.count)
        let origin = UserMessageImageStackSupport.collapsedFanOrigin(imageCount: imageParts.count)
        return ZStack(alignment: .topLeading) {
            ForEach((0..<visible).reversed(), id: \.self) { index in
                imageThumb(imageParts[index])
                    .rotationEffect(
                        .degrees(Double(index) * UserMessageImageStackSupport.stackRotationDegrees),
                        anchor: .bottomLeading
                    )
                    .offset(
                        x: origin.x + CGFloat(index) * UserMessageImageStackSupport.stackPeekX,
                        y: origin.y + CGFloat(index) * UserMessageImageStackSupport.stackPeekY
                    )
                    .shadow(
                        color: Color.black.opacity(index == 0 ? 0.04 : 0.16),
                        radius: index == 0 ? 1 : 3,
                        x: 0,
                        y: 1
                    )
                    .zIndex(Double(visible - index))
                    .allowsHitTesting(false)
            }
        }
    }

    private var expandedGrid: some View {
        let columns = [
            GridItem(
                .adaptive(
                    minimum: UserMessageImageStackSupport.thumbnailSize,
                    maximum: UserMessageImageStackSupport.thumbnailSize
                ),
                spacing: UserMessageImageStackSupport.thumbnailSpacing
            )
        ]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: UserMessageImageStackSupport.thumbnailSpacing) {
            ForEach(Array(imageParts.enumerated()), id: \.offset) { _, part in
                imageThumb(part)
            }
        }
        .padding(.top, JinSpacing.xSmall)
    }

    private func imageThumb(_ part: RenderedContentPart) -> some View {
        ContentPartView(
            part: part,
            isUser: true,
            deferCodeHighlightUpgrade: deferCodeHighlightUpgrade,
            payloadResolver: payloadResolver
        )
    }

    private func toggleExpanded() {
        if isExpanded {
            withAnimation(JinMotion.disclosure(expanding: false)) {
                isExpanded = false
            }
            return
        }

        if hasEverExpanded {
            withAnimation(JinMotion.disclosure(expanding: true)) {
                isExpanded = true
            }
            return
        }

        hasEverExpanded = true
        Task { @MainActor in
            await Task.yield()
            await Task.yield()
            withAnimation(JinMotion.disclosure(expanding: true)) {
                isExpanded = true
            }
        }
    }
}
