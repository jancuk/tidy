import SwiftUI

struct AIRequestLogView: View {
    @EnvironmentObject private var logStore: AIRequestLogStore

    var body: some View {
        VStack(spacing: 0) {
            pageHeader

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
                        ForEach(Array(logStore.entries.enumerated()), id: \.element.id) { index, entry in
                            AIRequestRowView(entry: entry)
                            if index < logStore.entries.count - 1 {
                                Divider().opacity(0.35).padding(.leading, 54)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var pageHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Requests")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(NSColor.labelColor))
                Text("\(logStore.entries.count) requests logged")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }
            Spacer()
            Button("Clear") { logStore.clear() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(logStore.entries.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }
}

private struct AIRequestRowView: View {
    let entry: AIRequestLogEntry
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Status icon
            ZStack {
                Circle()
                    .fill(entry.errorMessage == nil ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: entry.errorMessage == nil ? "checkmark" : "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(entry.errorMessage == nil ? Color.green : Color.red)
            }
            .padding(.leading, 8)

            VStack(alignment: .leading, spacing: 5) {
                // Badges + timestamp row
                HStack(spacing: 6) {
                    providerBadge
                    sourceBadge
                    Spacer()
                    Text(entry.createdAt, style: .relative)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                }

                // Request preview
                if !entry.requestPreview.isEmpty {
                    Text(entry.requestPreview)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(NSColor.labelColor))
                        .lineLimit(2)
                }

                // Status / error
                HStack(spacing: 6) {
                    if let errorMessage = entry.errorMessage {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                        Text(errorMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    } else {
                        if let code = entry.statusCode {
                            Text("HTTP \(code)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        }
                        Text("\(entry.durationMs)ms")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var providerBadge: some View {
        Text(entry.providerName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color(NSColor.secondaryLabelColor))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(NSColor.controlBackgroundColor), in: Capsule())
            .overlay(Capsule().stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
    }

    private var sourceBadge: some View {
        let isGrammar = entry.source == "grammar"
        let tint: Color = isGrammar ? .blue : .purple
        return Text(isGrammar ? "Grammar" : "Ask AI")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.25), lineWidth: 0.5))
    }
}
