import SwiftUI

struct DeveloperWorkflowsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(DeveloperWorkflowRegistry.all) { workflow in
                        workflowCard(workflow)
                    }
                }
                .padding(20)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Developer Workflows")
                    .font(.system(size: 17, weight: .bold))
                Text("Outcome-focused paths through Tidy's local tools and connected work context")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    private func workflowCard(_ workflow: DeveloperWorkflowDefinition) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: workflow.systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)
                    .background(
                        Color.accentColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
                Spacer()
                Label("Preview first", systemImage: "checkmark.shield")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.green)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(workflow.title)
                    .font(.system(size: 15, weight: .bold))
                Text(workflow.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(workflow.actionTitle) {
                appState.runWorkflow(workflow.id)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(
            Color(NSColor.controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }
}
