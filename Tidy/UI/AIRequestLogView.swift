import SwiftUI

struct AIRequestLogView: View {
    @EnvironmentObject private var logStore: AIRequestLogStore
    @State private var search = ""
    @State private var filter: RequestFilter = .all
    @State private var expanded: Set<UUID> = []
    @State private var confirmClear = false

    private enum RequestFilter: String, CaseIterable {
        case all = "All requests"
        case errors = "Needs attention"
        case grammar = "Grammar"
        case askAI = "Ask AI"
    }

    private var results: [AIRequestLogEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return logStore.entries.filter { entry in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .errors: matchesFilter = entry.errorMessage != nil
            case .grammar: matchesFilter = entry.source.hasPrefix("grammar")
            case .askAI: matchesFilter = entry.source == "ask-ai"
            }
            return matchesFilter && (query.isEmpty || [entry.requestPreview, entry.providerName, entry.errorMessage ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeader(title: "AI Requests", subtitle: "A little context for every request.") {
                Menu {
                    Button("Clear history…", role: .destructive) { confirmClear = true }.disabled(logStore.entries.isEmpty)
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().help("AI history options")
            }
            HStack(spacing: 8) {
                ForEach(RequestFilter.allCases, id: \.self) { item in
                    Button { filter = item } label: {
                        Text(item.rawValue).font(.system(size: 12, weight: filter == item ? .semibold : .regular))
                            .foregroundStyle(filter == item ? Color.primary : Color.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(filter == item ? WorkspaceDesign.inset : .clear, in: Capsule())
                    }.buttonStyle(.plain).accessibilityAddTraits(filter == item ? .isSelected : [])
                }
                Spacer(minLength: 12)
                WorkspaceSearchField(text: $search, placeholder: "Search requests", label: "Search AI requests").frame(maxWidth: 230)
            }.padding(.horizontal, 28).padding(.vertical, 14)
            if results.isEmpty {
                WorkspaceEmptyState(title: logStore.entries.isEmpty ? "Your AI work, remembered." : "No matching requests",
                                    detail: logStore.entries.isEmpty ? "Grammar fixes and Ask AI requests appear here with their provider and status." : "Try another filter or search term.", icon: "sparkle.magnifyingglass")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        Text("\(results.count) \(results.count == 1 ? "request" : "requests")").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        ForEach(results) { entry in requestCard(entry) }
                    }.padding(28).frame(maxWidth: 940).frame(maxWidth: .infinity)
                }
            }
        }.background(WorkspaceDesign.canvas)
        .confirmationDialog("Clear AI request history?", isPresented: $confirmClear) {
            Button("Clear history", role: .destructive) { logStore.clear() }
        } message: { Text("This removes saved request previews and diagnostic details from this Mac.") }
    }

    private func requestCard(_ entry: AIRequestLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: entry.errorMessage == nil ? "checkmark.circle" : "exclamationmark.circle")
                    .foregroundStyle(entry.errorMessage == nil ? Color.secondary : Color.orange)
                Text(entry.providerName).fontWeight(.semibold)
                Text(entry.source == "grammar-fallback" ? "Grammar fallback" : entry.source.hasPrefix("grammar") ? "Grammar" : entry.source == "ask-ai" ? "Ask AI" : entry.source).foregroundStyle(.secondary)
                Spacer()
                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
            }.font(.system(size: 12))
            Text(entry.requestPreview.isEmpty ? "No request preview was saved." : entry.requestPreview)
                .font(.system(size: 15)).lineSpacing(6)
                .lineLimit(expanded.contains(entry.id) ? nil : 3).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let error = entry.errorMessage {
                Label { Text(error) } icon: {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                    .font(.system(size: 12)).foregroundStyle(.primary).lineSpacing(4)
                    .lineLimit(expanded.contains(entry.id) ? nil : 2).textSelection(.enabled)
            }
            HStack {
                Button(expanded.contains(entry.id) ? "Hide details" : "Read details") {
                    if expanded.contains(entry.id) { expanded.remove(entry.id) } else { expanded.insert(entry.id) }
                }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Text(entry.errorMessage == nil ? "Completed · \(entry.durationMs.formatted()) ms" : "Request failed")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if expanded.contains(entry.id) {
                HStack(spacing: 20) {
                    Text("Saved request preview")
                    Text("Duration: \(entry.durationMs.formatted()) ms")
                    if let code = entry.statusCode { Text("HTTP \(code)") }
                }.font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(WorkspaceDesign.inset, in: RoundedRectangle(cornerRadius: 10))
            }
        }.padding(24).background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(WorkspaceDesign.border))
    }
}
