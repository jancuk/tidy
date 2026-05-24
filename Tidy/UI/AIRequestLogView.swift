import SwiftUI

struct AIRequestLogView: View {
    @EnvironmentObject private var logStore: AIRequestLogStore

    var body: some View {
        VStack(spacing: 0) {
            header
            if logStore.entries.isEmpty {
                ContentUnavailableView(
                    "No AI requests yet",
                    systemImage: "network",
                    description: Text("Every grammar fix and Ask AI call will be logged here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(logStore.entries) { entry in
                            AIRequestRowView(entry: entry)
                            if entry.id != logStore.entries.last?.id {
                                Divider().opacity(0.4).padding(.leading, 18)
                            }
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text("AI Requests")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(NSColor.labelColor))
            Spacer()
            Button("Clear") { logStore.clear() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(logStore.entries.isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct AIRequestRowView: View {
    let entry: AIRequestLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    providerBadge
                    sourceBadge
                    Spacer()
                    Text(entry.createdAt, style: .relative)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
                if !entry.requestPreview.isEmpty {
                    Text(entry.requestPreview)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(NSColor.labelColor))
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    if let errorMessage = entry.errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    } else {
                        if let code = entry.statusCode {
                            Text("HTTP \(code)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        }
                        Text("\(entry.durationMs)ms")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private var statusIcon: some View {
        Image(systemName: entry.errorMessage == nil ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.system(size: 14))
            .foregroundStyle(entry.errorMessage == nil ? Color.green : Color.red)
            .padding(.top, 1)
    }

    private var providerBadge: some View {
        Text(entry.providerName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color(NSColor.secondaryLabelColor))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(NSColor.controlBackgroundColor), in: Capsule())
    }

    private var sourceBadge: some View {
        let isGrammar = entry.source == "grammar"
        return Text(isGrammar ? "Grammar" : "Ask AI")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isGrammar ? Color.blue : Color.purple)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                (isGrammar ? Color.blue : Color.purple).opacity(0.1),
                in: Capsule()
            )
    }
}
