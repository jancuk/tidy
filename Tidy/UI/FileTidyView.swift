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

    private var scanTask: Task<Void, Never>?
    private let service: FileTidyService
    private let undoStore: FileTidyUndoLogStore

    init(service: FileTidyService = FileTidyService(), undoStore: FileTidyUndoLogStore) {
        self.service = service
        self.undoStore = undoStore
        undoSessions = undoStore.sessions
    }

    var selectedProposals: [FileTidyProposal] {
        scanResult?.proposals.filter { selectedProposalIDs.contains($0.id) } ?? []
    }

    func chooseFolder() {
        guard !isScanning, !isApplying else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan Folder"
        panel.message = "Tidy scans locally and shows every move before anything changes."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FolderAccessPolicy.allowsExplicitInspection(of: url) else {
            errorMessage = "For privacy, choose a specific folder instead of your entire home or Library folder."
            statusMessage = "No folder was accessed."
            return
        }
        selectedFolder = url
        scan()
    }

    func scan() {
        guard let selectedFolder else {
            errorMessage = FileTidyError.folderMissing.localizedDescription
            return
        }
        guard !isScanning, !isApplying else { return }
        isScanning = true
        errorMessage = nil
        statusMessage = "Scanning \(selectedFolder.lastPathComponent)…"
        let worker = Task.detached { [service] in try service.scan(rootURL: selectedFolder) }
        scanTask = Task {
            do {
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                scanResult = result
                selectedProposalIDs = Set(result.proposals.filter(\.isRecommendedByDefault).map(\.id))
                statusMessage = "\(result.records.count) items scanned · \(result.proposals.count) proposed moves"
            } catch is CancellationError {
                scanResult = nil
                selectedProposalIDs = []
                statusMessage = "Scan cancelled."
            } catch {
                scanResult = nil
                selectedProposalIDs = []
                errorMessage = error.localizedDescription
                statusMessage = "Scan failed."
            }
            isScanning = false
        }
    }

    func cancelScan() { scanTask?.cancel() }

    func clearUndoHistory() {
        undoStore.clear()
        undoSessions = undoStore.sessions
    }

    func applySelected() {
        guard !isApplying, !isScanning, let rootURL = scanResult?.rootURL, !selectedProposals.isEmpty else { return }
        isApplying = true
        errorMessage = nil
        statusMessage = "Applying \(selectedProposals.count) selected moves…"
        Task {
            do {
                let proposals = selectedProposals
                let journal = undoStore.recoveryJournal(rootURL: rootURL)
                let moves = try await Task.detached { [service] in
                    try service.apply(proposals, rootURL: rootURL, journal: journal)
                }.value
                undoStore.reload()
                undoSessions = undoStore.sessions
                statusMessage = "Moved \(moves.count) items. Undo log updated."
                isApplying = false
                scan()
            } catch {
                errorMessage = error.localizedDescription
                undoStore.reload()
                undoSessions = undoStore.sessions
                statusMessage = "Apply stopped. Review the undo log for any completed moves."
            }
            isApplying = false
        }
    }

    func undo(_ session: FileTidyUndoSession) {
        guard !isApplying, !isScanning else { return }
        isApplying = true
        errorMessage = nil
        statusMessage = "Undoing \(session.moveCount) moves…"
        Task {
            do {
                try await Task.detached { [service] in
                    try service.undo(session)
                }.value
                undoStore.remove(session)
                undoSessions = undoStore.sessions
                statusMessage = "Undid \(session.moveCount) moves."
                isApplying = false
                if selectedFolder != nil { scan() }
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = "Undo failed."
            }
            isApplying = false
        }
    }

    func selectAll()         { selectedProposalIDs = Set(scanResult?.proposals.map(\.id) ?? []) }
    func selectRecommended() { selectedProposalIDs = Set(scanResult?.proposals.filter(\.isRecommendedByDefault).map(\.id) ?? []) }
    func clearSelection()    { selectedProposalIDs.removeAll() }
}

// MARK: - Main view

struct FileTidyView: View {
    @EnvironmentObject private var viewModel: FileTidyViewModel

    var body: some View {
        VStack(spacing: 0) {
            pageHeader

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
            .disabled(viewModel.isApplying)
        }
        .background(WorkspaceDesign.canvas)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let result = viewModel.scanResult {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryGrid(result)
                    developerProjectsPanel(result)
                    groupsGrid(result)
                    proposalsPanel(result.proposals)
                    undoPanel
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else if !viewModel.isScanning {
            VStack {
                WorkspaceEmptyState(title: "A calmer folder starts here.",
                                    detail: "Choose a folder to review suggested moves. Nothing changes until you apply your selection.", icon: "folder.badge.gearshape")
                if !viewModel.undoSessions.isEmpty { ScrollView { undoPanel.padding(18) }.frame(maxHeight: 300) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Page header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            WorkspaceHeader(title: "File Tidy", subtitle: viewModel.selectedFolder?.path ?? "Review, organize, and get back to work.") {
                HStack(spacing: 8) {
                    Button { viewModel.chooseFolder() } label: {
                        Label("Choose Folder", systemImage: "folder")
                    }
                    if viewModel.isScanning { Button("Cancel scan") { viewModel.cancelScan() } }
                    Button { viewModel.scan() } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.selectedFolder == nil || viewModel.isScanning || viewModel.isApplying)

                    Button { viewModel.applySelected() } label: {
                        Label("Apply \(viewModel.selectedProposals.count) Moves", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(WorkspaceButtonStyle(prominent: true))
                    .disabled(viewModel.selectedProposals.isEmpty || viewModel.isScanning || viewModel.isApplying)
                }
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                if viewModel.isScanning {
                    ProgressView().controlSize(.small).frame(width: 14, height: 14)
                }
                HStack(spacing: 5) {
                    Circle()
                        .fill(viewModel.errorMessage != nil ? Color.red : Color.green)
                        .frame(width: 6, height: 6)
                    Text(viewModel.isScanning ? "Scanning…" : viewModel.statusMessage)
                        .lineLimit(3)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(viewModel.errorMessage != nil ? Color.red : Color.green)

                if let error = viewModel.errorMessage {
                    Text("·")
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }.padding(.horizontal, 28).padding(.top, 12)
        }
        .padding(.bottom, 14)
        .background(WorkspaceDesign.canvas)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    // MARK: Summary grid

    private func summaryGrid(_ result: FileTidyScanResult) -> some View {
        HStack(spacing: 10) {
            SummaryTile(icon: "doc.fill", accent: .blue, value: "\(result.records.count)", label: "Items scanned")
            SummaryTile(icon: "arrowshape.turn.up.right.fill", accent: .orange, value: "\(result.proposals.count)", label: "Proposed moves")
            SummaryTile(icon: "checkmark.circle.fill", accent: .green, value: "\(viewModel.selectedProposals.count)", label: "Approved")
            SummaryTile(icon: "internaldrive.fill", accent: .purple, value: ByteCountFormatter.string(fromByteCount: result.totalSize, countStyle: .file), label: "Scanned size")
        }
    }

    // MARK: Groups grid

    @ViewBuilder
    private func developerProjectsPanel(_ result: FileTidyScanResult) -> some View {
        if !result.developerProjects.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Developer projects").font(.headline)
                Text("Sizes include hidden build files, exclude Git metadata and symlinks, and assign nested projects separately. Review moves preserve files for undo; they do not free disk space.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(result.developerProjects) { project in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.url.lastPathComponent).font(.headline)
                            Text(project.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            Text(project.gitState.title).font(.caption)
                                .foregroundStyle(project.gitState == .clean ? Color.green : Color.orange)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(project.displaySize).font(.headline)
                            Text("\(project.artifactCount) generated folders · \(ByteCountFormatter.string(fromByteCount: project.artifactSize, countStyle: .file))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([project.url]) }
                    }.padding(.vertical, 6)
                }
            }.padding(16).background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        ForEach(Array(result.scanWarnings.enumerated()), id: \.offset) { _, warning in
            Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
        }
    }

    private func groupsGrid(_ result: FileTidyScanResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            GroupSummaryPanel(title: "File Type",     groups: result.typeGroups,    limit: 6)
            GroupSummaryPanel(title: "Date",          groups: result.dateGroups,    limit: 5)
            GroupSummaryPanel(title: "Project Hint",  groups: result.projectGroups, limit: 5)
            GroupSummaryPanel(title: "Usage",         groups: result.usageGroups,   limit: 5)
        }
    }

    // MARK: Proposals panel

    private func proposalsPanel(_ proposals: [FileTidyProposal]) -> some View {
        VStack(spacing: 0) {
            PanelTitleRow(title: "Preview Moves") {
                Button("Recommended") { viewModel.selectRecommended() }
                Button("All")         { viewModel.selectAll() }
                Button("None")        { viewModel.clearSelection() }
            }

            if proposals.isEmpty {
                Text("No cleanup moves found for this folder.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
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
                            Divider().opacity(0.4)
                        }
                    }
                }
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .tidyPanelStyle()
    }

    // MARK: Undo panel

    private var undoPanel: some View {
        VStack(spacing: 0) {
            PanelTitleRow(title: "Undo Log") {
                Text("\(viewModel.undoSessions.count) sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.undoSessions.isEmpty {
                Text("Applied moves will appear here with original and final paths.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(NSColor.textBackgroundColor))
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.undoSessions.prefix(5)) { session in
                        UndoSessionRow(session: session) { viewModel.undo(session) }
                        if session.id != viewModel.undoSessions.prefix(5).last?.id {
                            Divider().opacity(0.4)
                        }
                    }
                }
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .tidyPanelStyle()
    }
}

// MARK: - Summary tile

private struct SummaryTile: View {
    let icon: String
    let accent: Color
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(accent)
            }
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }
}

// MARK: - Scan loading overlay

private struct ScanLoadingView: View {
    let folderName: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            VStack(spacing: 5) {
                Text("Scanning \(folderName)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(NSColor.labelColor))
                Text("Reading files, grouping patterns, and preparing preview moves.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.14), radius: 20, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Group summary panel

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
                    .padding(.horizontal, 12)
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
                        .padding(12)
                }
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .frame(maxWidth: .infinity)
        .tidyPanelStyle()
    }
}

// MARK: - Proposal row

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

            VStack(alignment: .leading, spacing: 6) {
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
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 2) {
                    pathLine(label: "From", value: proposal.sourcePath)
                    pathLine(label: "To",   value: proposal.destinationPath)
                }

                HStack(spacing: 6) {
                    metadataChip(proposal.category.title)
                    metadataChip(proposal.usagePattern)
                    if let project = proposal.projectHint { metadataChip(project) }
                    Spacer()
                    Button("Inspect") { NSWorkspace.shared.activateFileViewerSelecting([proposal.sourceURL]) }
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
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
            .background(WorkspaceDesign.surface, in: Capsule())
            .overlay(Capsule().stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5))
    }
}

// MARK: - Undo session row

private struct UndoSessionRow: View {
    let session: FileTidyUndoSession
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.orange)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(session.moveCount) moves from \(URL(fileURLWithPath: session.rootPath).lastPathComponent)")
                    .font(.system(size: 13, weight: .semibold))
                Text(session.createdAt, style: .relative)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Undo") { undo() }
                .buttonStyle(WorkspaceButtonStyle())
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Risk pill

private struct RiskPill: View {
    let risk: FileTidyRisk

    var body: some View {
        Text(risk.title)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 0.5))
    }

    private var color: Color {
        switch risk {
        case .low:    .green
        case .review: .orange
        case .high:   .red
        }
    }
}

// MARK: - Panel title row

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
                .textCase(.uppercase)
                .kerning(0.3)
            Spacer()
            HStack(spacing: 8) { content }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(WorkspaceDesign.surface)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }
}

private extension View {
    func tidyPanelStyle() -> some View {
        clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
            )
    }
}
