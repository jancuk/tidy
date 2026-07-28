import SwiftUI

struct NotificationCenterView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var notificationService: UnifiedNotificationService
    @State private var expandedSources: Set<MCPIntegrationSource> = []

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    statusCard
                    ForEach(UnifiedNotificationService.notificationSources) { source in
                        sourceCard(source)
                    }
                }
                .padding(20)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications")
                    .font(.system(size: 17, weight: .bold))
                Text("Slack, Gmail, and Google Calendar in one place")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }
            Spacer()
            Button {
                Task { await notificationService.refresh() }
            } label: {
                if notificationService.isRefreshing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Refreshing…")
                    }
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(notificationService.isRefreshing)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    private var statusCard: some View {
        HStack(spacing: 10) {
            Image(systemName: notificationService.connectionStatus.hasPrefix("Connected")
                ? "checkmark.circle.fill"
                : "network")
                .foregroundStyle(notificationService.connectionStatus.hasPrefix("Connected")
                    ? Color.green
                    : Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(notificationService.connectionStatus)
                    .font(.system(size: 13, weight: .semibold))
                if let lastUpdatedAt = notificationService.lastUpdatedAt {
                    Text("Last updated \(lastUpdatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                } else {
                    Text("Configure an MCP server in Settings, then refresh.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
            }
            Spacer()
            Button("MCP Settings") {
                appState.openMCPSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .background(
            Color(NSColor.controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func sourceCard(_ source: MCPIntegrationSource) -> some View {
        let digest = notificationService.digests.first { $0.source == source }
        let error = notificationService.sourceErrors[source]

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: source.notificationSystemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint(for: source))
                    .frame(width: 34, height: 34)
                    .background(tint(for: source).opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title)
                        .font(.system(size: 14, weight: .bold))
                    if let digest {
                        Text("via \(digest.toolName) · \(digest.fetchedAt, style: .relative)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    }
                }
                Spacer()
                if let digest, !digest.rawPreview.isEmpty {
                    Button(expandedSources.contains(source) ? "Hide source" : "Show source") {
                        if expandedSources.contains(source) {
                            expandedSources.remove(source)
                        } else {
                            expandedSources.insert(source)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                }
            }

            if let digest {
                Text(.init(digest.summary))
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if expandedSources.contains(source) {
                    Divider().opacity(0.5)
                    Text(digest.rawPreview)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.orange)
            } else {
                Text(notificationService.isRefreshing ? "Loading…" : "No summary yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }
        }
        .padding(16)
        .background(
            Color(NSColor.controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }

    private func tint(for source: MCPIntegrationSource) -> Color {
        switch source {
        case .slack: .purple
        case .gmail: .red
        case .googleCalendar: .blue
        case .newRelic: .green
        case .jira: .indigo
        }
    }
}
