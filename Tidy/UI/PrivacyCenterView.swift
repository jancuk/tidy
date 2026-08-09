import SwiftUI

struct PrivacyCenterView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppDefaults.localOnlyAI) private var localOnlyAI = false
    @State private var storageItems: [PrivacyStorageItem] = []
    @State private var confirmation: PrivacyConfirmation?
    @State private var statusMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("Processing mode") {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(localOnlyAI ? Color.green : Color.accentColor)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Local-only AI")
                                .font(.system(size: 13, weight: .semibold))
                            Text("When enabled, Tidy blocks cloud and CLI AI providers. Ollama and LanguageTool remain available. Connected work services are contacted only when you explicitly use them or enable refresh.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(NSColor.secondaryLabelColor))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Toggle("", isOn: $localOnlyAI)
                            .labelsHidden()
                    }
                    .padding(14)
                }
                .cardStyle()
            }

            section("What can leave this Mac") {
                VStack(spacing: 0) {
                    dataFlowRow(
                        icon: "textformat",
                        title: "Selected text and Ask AI context",
                        detail: "Sent only to the provider you choose. Blocked for non-local providers in local-only mode."
                    )
                    Divider().opacity(0.45).padding(.leading, 52)
                    dataFlowRow(
                        icon: "point.3.connected.trianglepath.dotted",
                        title: "Connected work data",
                        detail: "Jira, Asana, and MCP are opt-in. Notification summaries send bounded tool output to the selected AI provider unless local-only mode is enabled."
                    )
                    Divider().opacity(0.45).padding(.leading, 52)
                    dataFlowRow(
                        icon: "folder",
                        title: "Files and clipboard history",
                        detail: "Stored and processed locally. File Tidy never moves anything outside the selected folder."
                    )
                }
                .cardStyle()
            }

            section("Stored locally") {
                VStack(spacing: 0) {
                    ForEach(Array(storageItems.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 12) {
                            Image(systemName: storageIcon(for: item.id))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 13, weight: .medium))
                                Text(item.detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                            }
                            Spacer()
                            Text(item.formattedSize)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        if index < storageItems.count - 1 {
                            Divider().opacity(0.45).padding(.leading, 52)
                        }
                    }
                }
                .cardStyle()

                HStack(spacing: 8) {
                    Button("Clear local history", role: .destructive) {
                        confirmation = .localHistory
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Remove credentials", role: .destructive) {
                        confirmation = .credentials
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Button("Personalize Tidy") {
                        appState.presentOnboarding()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if !statusMessage.isEmpty {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.green)
            }
        }
        .onAppear(perform: reloadInventory)
        .confirmationDialog(
            confirmation?.title ?? "",
            isPresented: Binding(
                get: { confirmation != nil },
                set: { if !$0 { confirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            if confirmation == .localHistory {
                Button("Clear all local history", role: .destructive) {
                    appState.clearAllLocalHistory()
                    statusMessage = "Local history was cleared."
                    reloadInventory()
                }
            } else if confirmation == .credentials {
                Button("Remove all saved credentials", role: .destructive) {
                    appState.disconnectAllIntegrations()
                    statusMessage = "Saved credentials and connection metadata were removed."
                    reloadInventory()
                }
            }
        } message: {
            Text(confirmation?.message ?? "")
        }
    }

    private func reloadInventory() {
        storageItems = PrivacyDataInventory.snapshot()
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
                .textCase(.uppercase)
                .kerning(0.5)
            content()
        }
    }

    private func dataFlowRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func storageIcon(for id: String) -> String {
        switch id {
        case "clipboard": "doc.on.clipboard"
        case "corrections": "checkmark.rectangle"
        case "ai-requests": "network"
        case "notifications": "bell"
        case "file-tidy": "arrow.uturn.backward.circle"
        default: "internaldrive"
        }
    }
}
private enum PrivacyConfirmation: Equatable {
    case localHistory
    case credentials

    var title: String {
        switch self {
        case .localHistory: "Clear all local history?"
        case .credentials: "Remove every saved credential?"
        }
    }

    var message: String {
        switch self {
        case .localHistory:
            "This clears clipboard history, corrections, AI diagnostics, notification summaries, and File Tidy undo records. It does not move or delete your files."
        case .credentials:
            "This removes provider keys and Jira, Asana, and MCP credentials from Keychain, then disconnects those integrations."
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        background(
            Color(NSColor.controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }
}
