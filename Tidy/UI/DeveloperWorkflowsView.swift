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
                .padding(30)
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
            }
        }
        .background(WorkspaceDesign.canvas)
    }

    private var header: some View {
        WorkspaceHeader(title: "Workflows", subtitle: "A good starting point for the work ahead.") { EmptyView() }
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
                    .font(.system(size: 13))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(workflow.actionTitle) {
                appState.runWorkflow(workflow.id)
            }
            .buttonStyle(WorkspaceButtonStyle(prominent: true))
            .controlSize(.small)
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 215, alignment: .topLeading)
        .background(
            WorkspaceDesign.surface,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }
}
