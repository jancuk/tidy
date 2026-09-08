import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProductivitySyncView: View {
    @EnvironmentObject private var sync: ProductivitySyncService
    @EnvironmentObject private var productivity: ProductivityService
    @Environment(\.dismiss) private var dismiss
    @State private var chosenMode: ProductivitySyncMode = .backup
    @State private var selectedBackup: ProductivityBackupFile?
    @State private var restoreComplete = false
    @State private var tab = "Connection"

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeader(title: "Google Drive", subtitle: "Keep your Today workspace close, wherever you work.") {
                Button("Done") { dismiss() }
            }
            HStack(spacing: 8) {
                ForEach(["Connection", "Backups", "Conflicts"], id: \.self) { value in
                    Button { tab = value; if value == "Backups" { Task { await sync.loadBackups() } } } label: {
                        Text(value == "Conflicts" && !sync.conflicts.isEmpty ? "Conflicts · \(sync.conflicts.count)" : value)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(tab == value ? WorkspaceDesign.inset : .clear, in: Capsule())
                    }.buttonStyle(.plain).accessibilityAddTraits(tab == value ? .isSelected : [])
                }
                Spacer()
                if sync.isBusy { ProgressView().controlSize(.small) }
            }.padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let message = sync.message {
                        Label(message, systemImage: "exclamationmark.circle").font(.callout).textSelection(.enabled)
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(WorkspaceDesign.inset, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if tab == "Connection" { connection }
                    else if tab == "Backups" { backupList }
                    else { conflictList }
                }.padding(24)
            }
        }
        .frame(width: 780, height: 640)
        .background(WorkspaceDesign.canvas)
        .onAppear { chosenMode = sync.mode }
        .confirmationDialog("Restore this backup?", isPresented: Binding(get: { selectedBackup != nil }, set: { if !$0 { selectedBackup = nil } }), presenting: selectedBackup) { file in
            Button("Restore saved versions") {
                Task { restoreComplete = await sync.restore(file.backup) }
            }
        } message: { file in
            Text("Restore \(file.backup.snapshot.items.count) \(file.backup.snapshot.items.count == 1 ? "item" : "items") and \(file.backup.snapshot.dailyNotes.count) focus notes from \(file.backup.createdAt.formatted()). Items added since this backup stay. Tidy saves a local recovery copy first. In two-way mode, restored versions also sync to your other Macs.")
        }
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(sync.status, systemImage: sync.isEnabled ? "externaldrive.badge.icloud" : "icloud")
                .font(.system(size: 23, weight: .medium))
            Text("Uses Google Drive for desktop. Choose the same folder in My Drive on each Mac, and make it available offline in Finder. Tidy works locally; Drive handles uploading and downloading.")
                .font(.system(size: 14)).lineSpacing(5).foregroundStyle(.secondary)
            Link("Google Drive setup guide", destination: URL(string: "https://support.google.com/drive/answer/13401938?hl=en")!)
                .font(.system(size: 12))
            VStack(alignment: .leading, spacing: 16) {
                Picker("Sync mode", selection: $chosenMode) {
                    ForEach(ProductivitySyncMode.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                Text(chosenMode == .backup
                     ? "Saves a new backup after workspace changes. Other Macs' edits are only brought in when you restore a backup."
                     : "Automatically receives changes from other Macs. Separate items merge automatically. When the same item changes on two Macs, both versions stay available for review.")
                    .font(.system(size: 13)).lineSpacing(4).foregroundStyle(.secondary)
                if let folder = sync.folder {
                    Label(folder.appendingPathComponent("Tidy Today").path, systemImage: "folder")
                        .font(.system(size: 12)).textSelection(.enabled).lineLimit(3)
                    HStack {
                        Button("Update now") { Task { await sync.syncNow() } }
                        if chosenMode != sync.mode {
                            Button("Apply mode") { _ = sync.connect(folder: folder, mode: chosenMode) }
                        }
                        Spacer()
                        Button("Disconnect") { sync.disconnect() }
                    }.buttonStyle(WorkspaceButtonStyle()).disabled(sync.isBusy)
                    if let last = sync.lastExchange {
                        Text("Last folder update: \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button(sync.isEnabled ? "Choose another Drive folder…" : "Choose Drive folder…", action: chooseFolder)
                    .buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(sync.isBusy || !productivity.storageReady)
            }.padding(20).background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 8) {
                Label("You choose what leaves this Mac", systemImage: "lock").font(.system(size: 13, weight: .medium))
                Text("Includes all Today tasks, notes, routines, completion history, archived items, and daily focus. Notification preferences and running timers stay on each Mac. Clipboard history, AI keys, and connected accounts are excluded.")
                Text("Folder updates do not confirm a cloud upload. Check Google Drive's menu bar status. Backups and version history are retained. Disconnect all Macs before removing version history; disconnecting leaves existing copies in Drive.")
            }.font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
        }
    }

    @ViewBuilder private var backupList: some View {
        HStack {
            Text("Recent backups").font(.system(size: 22, design: .serif))
            Spacer()
            Button("Refresh") { Task { await sync.loadBackups() } }.disabled(!sync.isEnabled || sync.isBusy)
            Button("Open backup…", action: openBackup).disabled(sync.isBusy)
        }.buttonStyle(WorkspaceButtonStyle())
        Button("Show local recovery copies") { sync.showRecoveryFolder() }.buttonStyle(.link)
        Text("Showing the latest 30 backups. Restore brings back saved versions and keeps items added afterward. Notification preferences and active timers are preserved on this Mac.")
            .font(.system(size: 13)).foregroundStyle(.secondary)
        if restoreComplete { Label("Backup restored. Your previous workspace has a local recovery copy.", systemImage: "checkmark.circle") }
        if sync.backups.isEmpty {
            Text(sync.isEnabled ? "No backups are available yet. Use Update now in Connection to save the first one." : "Connect your Drive folder to browse its backups.")
                .font(.system(size: 14)).foregroundStyle(.secondary).padding(.vertical, 32)
        }
        ForEach(sync.backups) { file in
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(file.backup.createdAt.formatted(date: .abbreviated, time: .shortened)).fontWeight(.medium)
                    Text("\(file.backup.device) · \(file.backup.snapshot.items.count) \(file.backup.snapshot.items.count == 1 ? "item" : "items") · \(file.backup.snapshot.dailyNotes.count) focus notes")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Restore…") { selectedBackup = file }.buttonStyle(WorkspaceButtonStyle()).disabled(sync.isBusy)
                    .accessibilityLabel("Restore backup from \(file.backup.createdAt.formatted()) on \(file.backup.device)")
            }.padding(18).background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder private var conflictList: some View {
        if sync.conflicts.isEmpty {
            WorkspaceEmptyState(title: "Everything has its place.", detail: "If the same item changes on different Macs, its versions appear here. No version is silently discarded.", icon: "checkmark.circle")
                .frame(height: 330)
        }
        ForEach(sync.conflicts) { conflict in
            VStack(alignment: .leading, spacing: 16) {
                Text(conflict.title).font(.system(size: 21, design: .serif))
                Text("Choose the version to use, or keep each version as a separate item. Alternative daily focus versions become notes.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Button("Keep all as separate items") {
                    if let first = conflict.versions.first { sync.resolve(conflict, keeping: first, keepBoth: true) }
                }.buttonStyle(WorkspaceButtonStyle(prominent: true))
                ForEach(conflict.versions) { revision in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(revision.device).fontWeight(.medium)
                            Spacer()
                            Text(revision.createdAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                        }.font(.caption)
                        Text(revision.title).font(.headline).textSelection(.enabled)
                        Text(revision.item?.body ?? revision.detail).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                        if let item = revision.item {
                            Text([item.kind.title, item.pinned ? "Pinned" : "", item.archivedAt != nil ? "Archived" : "", item.completedAt != nil ? "Completed" : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                            DisclosureGroup("Dates, tags & status") {
                                Text(revision.detail).font(.system(size: 12)).lineSpacing(5).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                            }.font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Button("Use this version") { sync.resolve(conflict, keeping: revision) }.buttonStyle(WorkspaceButtonStyle())
                            .accessibilityLabel("Use version from " + revision.device)
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 14))
                }

            }.padding(.bottom, 20).disabled(sync.isBusy)
        }
    }

    private func openBackup() {
        let panel = NSOpenPanel()
        panel.title = "Open a Tidy Today backup"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { selectedBackup = await sync.previewBackup(at: url) }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Google Drive folder for Today"
        panel.message = "Tidy creates a ‘Tidy Today’ folder here and starts \(chosenMode.rawValue.lowercased()). On another Mac, choose the same parent folder."
        panel.prompt = chosenMode == .backup ? "Start backup" : "Start sync"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = sync.folder ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/CloudStorage")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = sync.connect(folder: url, mode: chosenMode)
    }
}
