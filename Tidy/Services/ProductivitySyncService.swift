import AppKit
import Combine
import Foundation

@MainActor
final class ProductivitySyncService: ObservableObject {
    private struct Configuration: Codable {
        var bookmark: Data
        var mode: ProductivitySyncMode
    }

    @Published private(set) var folder: URL?
    @Published private(set) var mode: ProductivitySyncMode = .backup
    @Published private(set) var isBusy = false
    @Published private(set) var lastExchange: Date?
    @Published private(set) var message: String?
    @Published private(set) var backups: [ProductivityBackupFile] = []
    @Published private(set) var conflicts: [ProductivitySyncConflict] = []
    var isEnabled: Bool { folder != nil }
    var status: String {
        if isBusy { return "Updating Drive folder…" }
        if message != nil { return "Sync needs attention" }
        if !conflicts.isEmpty { return "\(conflicts.count) \(conflicts.count == 1 ? "conflict" : "conflicts") to review" }
        if folder == nil { return "Sync is off" }
        if needsSync { return "Changes waiting for Drive folder" }
        return lastExchange == nil ? "Waiting for first backup" : "Drive folder up to date"
    }

    private let workspace: ProductivityService
    private let configurationURL: URL
    private let recoveryDirectory: URL
    private let transport: ProductivitySyncTransport
    private let device: String
    private var subscription: AnyCancellable?
    private var timer: AnyCancellable?
    private var scheduled: Task<Void, Never>?
    private var lastBackup: ProductivitySnapshot?
    private var pendingBackup: ProductivityBackup?
    private var generation = UUID()
    @Published private var needsSync = false

    init(workspace: ProductivityService, directory: URL, device: String = Host.current().localizedName ?? "Mac", transport: ProductivitySyncTransport = ProductivitySyncTransport()) {
        self.workspace = workspace
        self.device = device
        self.transport = transport
        configurationURL = directory.appendingPathComponent("productivity-sync-settings.json")
        recoveryDirectory = directory.appendingPathComponent("Today Recovery")
        do {
            if FileManager.default.fileExists(atPath: configurationURL.path) {
                let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configurationURL))
                var stale = false
                folder = try URL(resolvingBookmarkData: config.bookmark, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale)
                mode = config.mode
                if stale { message = "Folder access has changed. Choose your Google Drive folder again."; folder = nil }
            }
        } catch { message = "Could not reconnect your Drive folder: \(error.localizedDescription)" }
        workspace.syncDeviceName = device
        subscription = workspace.$snapshot.dropFirst().sink { [weak self] snapshot in
            guard let self else { return }
            conflicts = ProductivitySyncMerge.conflicts(snapshot.syncJournal ?? [])
            schedule()
        }
        conflicts = ProductivitySyncMerge.conflicts(workspace.snapshot.syncJournal ?? [])
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.publish(every: 15, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.schedule() }
        schedule()
    }

    @discardableResult
    func connect(folder: URL, mode: ProductivitySyncMode) -> Bool {
        guard !isBusy else { return false }
        do {
            let accessed = folder.startAccessingSecurityScopedResource()
            defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
            let bookmark = try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            try FileManager.default.createDirectory(at: configurationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Configuration(bookmark: bookmark, mode: mode)).write(to: configurationURL, options: .atomic)
            SecureLocalStorage.protectFile(at: configurationURL)
            generation = UUID()
            self.folder = folder; self.mode = mode
            lastBackup = nil; pendingBackup = nil; lastExchange = nil; message = nil; backups = []
            start()
            schedule()
            return true
        } catch { message = "Could not connect this folder: \(error.localizedDescription)"; return false }
    }

    func disconnect() {
        guard !isBusy else { return }
        do {
            if FileManager.default.fileExists(atPath: configurationURL.path) { try FileManager.default.removeItem(at: configurationURL) }
            generation = UUID()
            scheduled?.cancel(); scheduled = nil
            folder = nil; lastExchange = nil; message = nil; backups = []; lastBackup = nil; pendingBackup = nil
        } catch { message = "Could not disconnect: \(error.localizedDescription)" }
    }

    func syncNow() async {
        guard let folder, !isBusy else { return }
        guard workspace.storageReady else { message = "Reload your local workspace before syncing."; return }
        guard workspace.editorItem == nil, workspace.editingDailyNote == nil else {
            message = "Finish editing to receive changes from your other Macs. Your draft stays here."
            return
        }
        needsSync = false
        isBusy = true
        let currentGeneration = generation
        defer { isBusy = false; if needsSync { schedule() } }
        do {
            guard workspace.prepareSync() else { throw ProductivityError.invalid(workspace.errorMessage ?? "Could not prepare your workspace.") }
            let snapshot = workspace.snapshot
            let content = ProductivityBackup(snapshot: snapshot, device: device)
            if content.snapshot != lastBackup, pendingBackup?.snapshot != content.snapshot { pendingBackup = content }
            let backup = content.snapshot == lastBackup ? nil : pendingBackup
            let remote = try await transport.exchange(folder: folder, revisions: mode == .twoWay ? snapshot.syncJournal ?? [] : nil, backup: backup)
            guard generation == currentGeneration else { return }
            if backup != nil { lastBackup = content.snapshot; pendingBackup = nil }
            // A draft may have opened while Drive was reading its files.
            if workspace.editorItem != nil || workspace.editingDailyNote != nil {
                message = "Backup saved. Finish editing to receive changes from your other Macs."
                return
            }
            if mode == .twoWay {
                guard workspace.receiveSync(remote) else { throw ProductivityError.invalid(workspace.errorMessage ?? "Could not merge changes.") }
            }
            lastExchange = Date()
            message = nil
        } catch { message = "\(error.localizedDescription) Local edits remain saved. Tidy will retry automatically." }
    }

    func loadBackups() async {
        guard let folder, !isBusy else { return }
        isBusy = true
        defer { isBusy = false; if needsSync { schedule() } }
        do { backups = try await transport.backups(folder: folder) }
        catch { message = "Could not read backups: \(error.localizedDescription)" }
    }

    @discardableResult
    func restore(_ backup: ProductivityBackup) async -> Bool {
        guard !isBusy, workspace.storageReady, workspace.editorItem == nil, workspace.editingDailyNote == nil else { return false }
        isBusy = true
        defer { isBusy = false; if needsSync { schedule() } }
        do {
            try backup.validate()
            let before = workspace.snapshot
            try await transport.writeBackup(ProductivityBackup(snapshot: before, device: device), directory: recoveryDirectory)
            guard workspace.snapshot == before, workspace.editorItem == nil, workspace.editingDailyNote == nil else {
                throw ProductivityError.invalid("Your workspace changed during restore. Finish editing, then try again.")
            }
            guard workspace.restoreContents(backup.snapshot) else { throw ProductivityError.invalid(workspace.errorMessage ?? "Restore failed.") }
            lastBackup = nil
            message = nil
            schedule()
            return true
        } catch { message = "Could not restore: \(error.localizedDescription)"; return false }
    }

    func previewBackup(at url: URL) async -> ProductivityBackupFile? {
        guard !isBusy else { return nil }
        isBusy = true
        defer { isBusy = false; if needsSync { schedule() } }
        do { return try await transport.backupFile(at: url) }
        catch { message = "Could not open this backup: \(error.localizedDescription)"; return nil }
    }

    func showRecoveryFolder() {
        do {
            try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(recoveryDirectory)
        } catch { message = error.localizedDescription }
    }

    func resolve(_ conflict: ProductivitySyncConflict, keeping revision: ProductivitySyncRevision, keepBoth: Bool = false) {
        guard workspace.resolveSyncConflict(conflict, keeping: revision, keepBoth: keepBoth) else { return }
        schedule()
    }

    private func schedule() {
        guard isEnabled else { return }
        needsSync = true
        guard !isBusy else { return }
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }
}
