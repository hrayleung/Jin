import SwiftUI

struct AgentApprovalView: View {
    let request: AgentApprovalRequest
    let onResolve: (AgentApprovalChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AgentApprovalHeaderView(
                title: request.title,
                description: AgentApprovalPresentationSupport.requestDescription(for: request.kind)
            )

            Divider()
                .padding(.horizontal, JinSpacing.medium)

            ScrollView {
                AgentApprovalRequestContentView(kind: request.kind)
                    .padding(JinSpacing.large)
            }

            Divider()
                .padding(.horizontal, JinSpacing.medium)

            AgentApprovalButtonRow(onResolve: onResolve)
                .padding(.horizontal, JinSpacing.large)
                .padding(.vertical, JinSpacing.medium)
        }
        .background(
            RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)
                .fill(.regularMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)
                .stroke(JinSemanticColor.separator.opacity(0.45), lineWidth: JinStrokeWidth.hairline)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 8)
        .interactiveDismissDisabled(true)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 200, idealHeight: 360)
    }
}
