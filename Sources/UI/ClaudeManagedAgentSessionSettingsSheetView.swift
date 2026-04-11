import SwiftUI

struct ClaudeManagedAgentSessionSettingsSheetView: View {
    @Binding var agentIDDraft: String
    @Binding var environmentIDDraft: String
    @Binding var agentDisplayNameDraft: String
    @Binding var environmentDisplayNameDraft: String
    @Binding var draftError: String?

    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JinSpacing.medium) {
                    configurationSection
                    detailsSection
                }
                .padding(JinSpacing.large)
            }
            .background {
                JinSemanticColor.detailSurface
                    .ignoresSafeArea()
            }
            .navigationTitle("Claude Managed Agent")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave() }
                }
            }
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 360, idealHeight: 420)
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Label("Runtime IDs", systemImage: "person.crop.square")
                .font(.subheadline.weight(.semibold))

            TextField("Agent ID", text: $agentIDDraft, prompt: Text("agent_..."))
                .textFieldStyle(.roundedBorder)
            TextField("Environment ID", text: $environmentIDDraft, prompt: Text("env_..."))
                .textFieldStyle(.roundedBorder)

            Text("Jin creates or resumes a Managed Agents session for this chat thread using the selected Agent and Environment IDs.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let draftError, !draftError.isEmpty {
                Text(draftError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(JinSpacing.medium)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Label("Optional Labels", systemImage: "tag")
                .font(.subheadline.weight(.semibold))

            TextField("Agent Name", text: $agentDisplayNameDraft, prompt: Text("Claude coding agent"))
                .textFieldStyle(.roundedBorder)
            TextField("Environment Name", text: $environmentDisplayNameDraft, prompt: Text("macOS workspace"))
                .textFieldStyle(.roundedBorder)

            Text("These labels are only for Jin’s local UI and do not change the remote resource names.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(JinSpacing.medium)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }
}
