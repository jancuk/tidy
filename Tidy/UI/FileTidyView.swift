import AppKit
import SwiftUI

@MainActor
final class FileTidyViewModel: ObservableObject {
    @Published var selectedFolder: URL?
    @Published var scanResult: FileTidyScanResult?
    @Published var selectedProposalIDs: Set<UUID> = []
    @Published var isScanning = false
    @Published var isApplying = false
    @Published var statusMessage = "Choose a folder to preview cleanup suggestions."
    @Published var errorMessage: String?
    @Published var undoSessions: [FileTidyUndoSession] = []

    private let service = FileTidyService()
    private let undoStore = FileTidyUndoLogStore()

    init() {
        undoSessions = undoStore.sessions
    }

    var selectedProposals: [FileTidyProposal] {
        scanResult?.proposals.filter { selectedProposalIDs.contains($0.id) } ?? []
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan Folder"
        panel.message = "Tidy scans locally and shows every move before anything changes."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectedFolder = url
        scan()
    }

    func scan() {
        guard let selectedFolder else {
            errorMessage = FileTidyError.folderMissing.localizedDescription
            return
        }

        isScanning = true
        errorMessage = nil
        statusMessage = "Scanning \(selectedFolder.lastPathComponent)..."

        Task {
            do {
                let result = try await Task.detached { [service] in
                    try service.scan(rootURL: selectedFolder)
                }.value
                scanResult = result
                selectedProposalIDs = Set(result.proposals.filter(\.isRecommendedByDefault).map(\.id))
                statusMessage = "\(result.records.count) items scanned, \(result.proposals.count) proposed moves."
            } catch {
                scanResult = nil
                selectedProposalIDs = []
                errorMessage = error.localizedDescription
                statusMessage = "Scan failed."
            }
            isScanning = false
        }
    }

    func applySelected() {
        guard let rootURL = scanResult?.rootURL, !selectedProposals.isEmpty else { return }

        isApplying = true
        errorMessage = nil
        statusMessage = "Applying \(selectedProposals.count) selected moves..."

        Task {
            do {
                let proposals = selectedProposals
                let moves = try await Task.detached { [service] in
                    try service.apply(proposals, rootURL: rootURL)
                }.value
                undoStore.append(rootURL: rootURL, moves: moves)
                undoSessions = undoStore.sessions
                statusMessage = "Moved \(moves.count) items. Undo log updated."
                scan()
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = "Apply failed."
            }
            isApplying = false
        }
    }

    func undo(_ session: FileTidyUndoSession) {
        isApplying = true
        errorMessage = nil
        statusMessage = "Undoing \(session.moveCount) moves..."

        Task {
            do {
                try await Task.detached { [service] in
                    try service.undo(session)
                }.value
                undoStore.remove(session)
                undoSessions = undoStore.sessions
                statusMessage = "Undid \(session.moveCount) moves."
                if selectedFolder != nil {
                    scan()
                }
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = "Undo failed."
            }
            isApplying = false
        }
    }

    func selectAll() {
        selectedProposalIDs = Set(scanResult?.proposals.map(\.id) ?? [])
    }

    func selectRecommended() {
        selectedProposalIDs = Set(scanResult?.proposals.filter(\.isRecommendedByDefault).map(\.id) ?? [])
    }

    func clearSelection() {
        selectedProposalIDs.removeAll()
    }
}

struct FileTidyView: View {
    @StateObject private var viewModel = FileTidyViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                content
                    .opacity(viewModel.isScanning && viewModel.scanResult != nil ? 0.38 : 1)
                    .disabled(viewModel.isScanning)

                if viewModel.isScanning {
                    ScanLoadingView(folderName: viewModel.selectedFolder?.lastPathComponent ?? "folder")
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(.easeInOut(duration: 0.16), value: viewModel.isScanning)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        if let result = viewModel.scanResult {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summaryGrid(result)
                    groupsGrid(result)
                    proposalsPanel(result.proposals)
                    undoPanel
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else if !viewModel.isScanning {
            ContentUnavailableView(
                "Preview Folder Cleanup",
                systemImage: "folder.badge.gearshape",
                description: Text("Select Downloads, Desktop, or a project-adjacent folder. Tidy will scan locally and wait for approval before moving anything.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("File Tidy")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(NSColor.labelColor))
                    Text(viewModel.selectedFolder?.path ?? "Rule-based, local-only cleanup for messy folders.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                HStack(spacing: 7) {
                    Button {
                        viewModel.chooseFolder()
                    } label: {
                        Label("Choose", systemImage: "folder")
                    }
                    Button {
                        viewModel.scan()
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.selectedFolder == nil || viewModel.isScanning)
                    Button {
                        viewModel.applySelected()
                    } label: {
                        Label("Apply", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.selectedProposals.isEmpty || viewModel.isScanning || viewModel.isApplying)
                }
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                if viewModel.isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                }
                StatusBadge(
                    text: viewModel.isScanning ? "Scanning..." : viewModel.statusMessage,
                    isError: viewModel.errorMessage != nil
                )
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func summaryGrid(_ result: FileTidyScanResult) -> some View {
        HStack(spacing: 10) {
            SummaryTile(icon: "doc", value: "\(result.records.count)", label: "Items scanned")
            SummaryTile(icon: "arrowshape.turn.up.right", value: "\(result.proposals.count)", label: "Proposed moves")
            SummaryTile(icon: "checkmark.circle", value: "\(viewModel.selectedProposals.count)", label: "Approved")
            SummaryTile(icon: "internaldrive", value: ByteCountFormatter.string(fromByteCount: result.totalSize, countStyle: .file), label: "Scanned size")
        }
    }

    private func groupsGrid(_ result: FileTidyScanResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            GroupSummaryPanel(title: "Type", groups: result.typeGroups, limit: 6)
            GroupSummaryPanel(title: "Date", groups: result.dateGroups, limit: 5)
            GroupSummaryPanel(title: "Project Hint", groups: result.projectGroups, limit: 5)
            GroupSummaryPanel(title: "Usage", groups: result.usageGroups, limit: 5)
        }
    }

    private func proposalsPanel(_ proposals: [FileTidyProposal]) -> some View {
        VStack(spacing: 0) {
            PanelTitleRow(title: "Preview Moves") {
                Button("Recommended") { viewModel.selectRecommended() }
                Button("All") { viewModel.selectAll() }
                Button("None") { viewModel.clearSelection() }
            }

            if proposals.isEmpty {
                Text("No cleanup moves found for this folder.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(NSColor.textBackgroundColor))
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(proposals) { proposal in
                        ProposalRow(
                            proposal: proposal,
                            isSelected: viewModel.selectedProposalIDs.contains(proposal.id)
                        ) {
                            if viewModel.selectedProposalIDs.contains(proposal.id) {
                                viewModel.selectedProposalIDs.remove(proposal.id)
                            } else {
                                viewModel.selectedProposalIDs.insert(proposal.id)
                            }
                        }
                        if proposal.id != proposals.last?.id {
                            Divider().opacity(0.5)
                        }
                    }
                }
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .panelFrame()
    }

    private var undoPanel: some View {
        VStack(spacing: 0) {
            PanelTitleRow(title: "Undo Log") {
                Text("\(viewModel.undoSessions.count) sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.undoSessions.isEmpty {
                Text("Applied moves will appear here with their original and final paths.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(NSColor.textBackgroundColor))
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.undoSessions.prefix(5)) { session in
                        UndoSessionRow(session: session) {
                            viewModel.undo(session)
                        }
                        if session.id != viewModel.undoSessions.prefix(5).last?.id {
                            Divider().opacity(0.5)
                        }
                    }
                }
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .panelFrame()
    }
}

private struct SummaryTile: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                Spacer()
            }
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.separator.opacity(0.6), lineWidth: 0.5))
    }
}

private struct ScanLoadingView: View {
    let folderName: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            VStack(spacing: 4) {
                Text("Scanning \(folderName)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(NSColor.labelColor))
                Text("Reading files, grouping patterns, and preparing preview moves.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GroupSummaryPanel: View {
    let title: String
    let groups: [FileTidyGroupSummary]
    let limit: Int

    var body: some View {
        VStack(spacing: 0) {
            PanelTitleRow(title: title)
            VStack(spacing: 0) {
                ForEach(groups.prefix(limit)) { group in
                    HStack(spacing: 8) {
                        Text(group.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer()
                        Text("\(group.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    if group.id != groups.prefix(limit).last?.id {
                        Divider().opacity(0.35)
                    }
                }
                if groups.isEmpty {
                    Text("No items")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .frame(maxWidth: .infinity)
        .panelFrame()
    }
}

private struct ProposalRow: View {
    let proposal: FileTidyProposal
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(get: { isSelected }, set: { _ in toggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .padding(.top, 2)

            Image(systemName: proposal.category.systemImage)
                .font(.system(size: 14))
                .foregroundStyle(iconColor)
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(proposal.fileName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(proposal.displaySize)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    RiskPill(risk: proposal.risk)
                    Spacer()
                }

                Text(proposal.reason)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .lineLimit(2)

                VStack(alignment: .leading, spacing: 2) {
                    pathLine(label: "From", value: proposal.sourcePath)
                    pathLine(label: "To", value: proposal.destinationPath)
                }

                HStack(spacing: 8) {
                    metadataChip(proposal.category.title)
                    metadataChip(proposal.usagePattern)
                    if let project = proposal.projectHint {
                        metadataChip(project)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var iconColor: Color {
        switch proposal.risk {
        case .low:    .green
        case .review: .orange
        case .high:   .red
        }
    }

    private func pathLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func metadataChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color(NSColor.secondaryLabelColor))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color(NSColor.controlBackgroundColor), in: Capsule())
    }
}

private struct UndoSessionRow: View {
    let session: FileTidyUndoSession
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.system(size: 16))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(session.moveCount) moves from \(URL(fileURLWithPath: session.rootPath).lastPathComponent)")
                    .font(.system(size: 13, weight: .semibold))
                Text(session.createdAt, style: .relative)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Undo") { undo() }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct RiskPill: View {
    let risk: FileTidyRisk

    var body: some View {
        Text(risk.title)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }

    private var color: Color {
        switch risk {
        case .low:    .green
        case .review: .orange
        case .high:   .red
        }
    }
}

private struct StatusBadge: View {
    let text: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isError ? Color.red : Color.green)
                .frame(width: 6, height: 6)
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(isError ? Color.red : Color.green)
    }
}

private struct PanelTitleRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(title: String, @ViewBuilder content: () -> Content = { EmptyView() }) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
            Spacer()
            HStack(spacing: 7) { content }
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }
}

private extension View {
    func panelFrame() -> some View {
        clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.separator, lineWidth: 0.5))
    }
}
