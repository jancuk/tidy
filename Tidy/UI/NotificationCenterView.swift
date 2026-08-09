import SwiftUI

struct NotificationCenterView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var notificationService: UnifiedNotificationService
    @State private var expandedSources: Set<MCPIntegrationSource> = []
    @State private var selectedSource: MCPIntegrationSource?

    private let overviewColumns = [
        GridItem(.adaptive(minimum: 210), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    connectionBanner
                    briefingCard
                    sourceOverview
                    sourceFilter

                    ForEach(visibleSources) { source in
                        sourceCard(source)
                    }
                }
                .padding(20)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Daily Briefing")
                    .font(.system(size: 18, weight: .bold))
                Text("A low-noise engineering summary from Slack, Gmail, and Calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }

            Spacer()

            Text(
                Date(),
                format: .dateTime.weekday(.wide).month(.abbreviated).day()
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color(NSColor.secondaryLabelColor))

            Button {
                Task { await notificationService.refresh() }
            } label: {
                if notificationService.isRefreshing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Refreshing…")
                    }
                } else {
                    Label("Refresh brief", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(notificationService.isRefreshing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    private var connectionBanner: some View {
        HStack(spacing: 11) {
            Image(systemName: connectionIcon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(connectionColor)
                .frame(width: 30, height: 30)
                .background(connectionColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(notificationService.connectionStatus)
                    .font(.system(size: 12, weight: .semibold))
                Text(connectionDetail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }

            Spacer()

            Text("\(notificationService.digests.count)/3 sources ready")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))

            Button("Integration settings") {
                appState.openMCPSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Color(NSColor.controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.45), lineWidth: 0.5)
        )
    }

    private var briefingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("ENGINEER BRIEF", systemImage: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(0.7)
                    .foregroundStyle(Color.accentColor)

                Spacer()

                if let generatedAt = notificationService.briefing?.generatedAt {
                    Text("Generated \(generatedAt, style: .relative)")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
            }

            if let briefing = notificationService.briefing {
                Text(.init(briefing.summary))
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if notificationService.isRefreshing {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text("Building your engineering brief…")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your engineering day, summarized")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Refresh to surface urgent replies, blockers, decisions, and meeting preparation.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.12),
                    Color(NSColor.controlBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.accentColor.opacity(0.22), lineWidth: 0.8)
        )
    }

    private var sourceOverview: some View {
        LazyVGrid(columns: overviewColumns, spacing: 12) {
            ForEach(UnifiedNotificationService.notificationSources) { source in
                sourceOverviewTile(source)
            }
        }
    }

    private func sourceOverviewTile(_ source: MCPIntegrationSource) -> some View {
        let hasDigest = notificationService.digests.contains { $0.source == source }
        let hasError = notificationService.sourceErrors[source] != nil
        let stateText = hasDigest
            ? "Ready"
            : (hasError ? "Needs attention" : (notificationService.isRefreshing ? "Loading" : "Waiting"))
        let stateColor: Color = hasDigest ? .green : (hasError ? .orange : .secondary)

        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedSource = selectedSource == source ? nil : source
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: source.notificationSystemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint(for: source))
                    .frame(width: 34, height: 34)
                    .background(
                        tint(for: source).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(source.title)
                        .font(.system(size: 12, weight: .semibold))
                    HStack(spacing: 5) {
                        Circle()
                            .fill(stateColor)
                            .frame(width: 6, height: 6)
                        Text(stateText)
                            .font(.system(size: 10))
                            .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    }
                }

                Spacer()
            }
            .padding(12)
            .background(
                selectedSource == source
                    ? Color.accentColor.opacity(0.10)
                    : Color(NSColor.controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        selectedSource == source
                            ? Color.accentColor.opacity(0.55)
                            : Color(NSColor.separatorColor).opacity(0.42),
                        lineWidth: selectedSource == source ? 1 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var sourceFilter: some View {
        HStack(spacing: 7) {
            Text("Source detail")
                .font(.system(size: 12, weight: .bold))

            Spacer()

            filterButton("All", source: nil)
            ForEach(UnifiedNotificationService.notificationSources) { source in
                filterButton(source.title, source: source)
            }
        }
        .padding(.top, 4)
    }

    private func filterButton(
        _ title: String,
        source: MCPIntegrationSource?
    ) -> some View {
        let isSelected = selectedSource == source
        return Button(title) {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedSource = source
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
        .foregroundStyle(
            isSelected ? Color.white : Color(NSColor.secondaryLabelColor)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .stroke(Color(NSColor.separatorColor).opacity(isSelected ? 0 : 0.5), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func sourceCard(_ source: MCPIntegrationSource) -> some View {
        let digest = notificationService.digests.first { $0.source == source }
        let error = notificationService.sourceErrors[source]

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Image(systemName: source.notificationSystemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint(for: source))
                    .frame(width: 36, height: 36)
                    .background(
                        tint(for: source).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title)
                        .font(.system(size: 14, weight: .bold))
                    Text(source.notificationSubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }

                Spacer()

                if let digest {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Updated \(digest.fetchedAt, style: .relative)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        Text(digest.toolName)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                    }
                }

                if let digest, !digest.rawPreview.isEmpty {
                    Button {
                        if expandedSources.contains(source) {
                            expandedSources.remove(source)
                        } else {
                            expandedSources.insert(source)
                        }
                    } label: {
                        Image(
                            systemName: expandedSources.contains(source)
                                ? "chevron.up"
                                : "chevron.down"
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .help(expandedSources.contains(source) ? "Hide source data" : "Show source data")
                }
            }

            if let digest {
                Text(.init(digest.summary))
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if expandedSources.contains(source) {
                    Divider().opacity(0.45)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SOURCE PREVIEW")
                            .font(.system(size: 9, weight: .bold))
                            .kerning(0.6)
                            .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                        Text(digest.rawPreview)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color(NSColor.secondaryLabelColor))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else if let error {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("This source needs attention")
                            .font(.system(size: 12, weight: .semibold))
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(NSColor.secondaryLabelColor))
                            .textSelection(.enabled)
                        Button("Review integration settings") {
                            appState.openMCPSettings()
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                    }
                }
            } else {
                HStack(spacing: 8) {
                    if notificationService.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "tray")
                            .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                    }
                    Text(
                        notificationService.isRefreshing
                            ? "Reading \(source.title)…"
                            : "No summary yet. Refresh the brief to check this source."
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
            }
        }
        .padding(16)
        .background(
            Color(NSColor.controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.45), lineWidth: 0.5)
        )
    }

    private var visibleSources: [MCPIntegrationSource] {
        guard let selectedSource else {
            return UnifiedNotificationService.notificationSources
        }
        return [selectedSource]
    }

    private var connectionIcon: String {
        if notificationService.isRefreshing {
            return "arrow.triangle.2.circlepath"
        }
        if notificationService.connectionStatus.hasPrefix("Connected") {
            return "checkmark.circle.fill"
        }
        if notificationService.connectionStatus.hasPrefix("Connection failed") {
            return "exclamationmark.triangle.fill"
        }
        return "network"
    }

    private var connectionColor: Color {
        if notificationService.connectionStatus.hasPrefix("Connected") {
            return .green
        }
        if notificationService.connectionStatus.hasPrefix("Connection failed") {
            return .orange
        }
        return .accentColor
    }

    private var connectionDetail: String {
        if let lastUpdatedAt = notificationService.lastUpdatedAt {
            return "Last refreshed \(lastUpdatedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Configure a read-only MCP connection, then refresh."
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
