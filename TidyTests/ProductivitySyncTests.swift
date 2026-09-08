import Foundation
import Testing
@testable import Tidy

@MainActor
struct ProductivitySyncTests {
    private func workspace(_ name: String) -> ProductivityService {
        let value = ProductivityService(store: ProductivityStore(fileURL: nil), notifier: SilentProductivityNotifications())
        value.syncDeviceName = name
        return value
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TidySyncTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func pair() -> (ProductivityService, ProductivityService) {
        let first = workspace("Office Mac"), second = workspace("Home Mac")
        #expect(first.quickCapture("Shared note\nOriginal body", kind: .note))
        #expect(first.prepareSync())
        #expect(second.prepareSync())
        #expect(second.receiveSync(first.snapshot.syncJournal!))
        return (first, second)
    }

    @Test func separateOfflineEditsMergeWithoutUsingDeviceClocks() throws {
        let (first, second) = pair()
        #expect(first.quickCapture("Office task", kind: .task))
        #expect(second.quickCapture("Home task", kind: .task))
        let a = first.snapshot.syncJournal!, b = second.snapshot.syncJournal!
        #expect(first.receiveSync(b.reversed()))
        #expect(second.receiveSync(a))
        #expect(Set(first.snapshot.items.map(\.id)) == Set(second.snapshot.items.map(\.id)))
        #expect(first.snapshot.items.count == 3)
        #expect(ProductivitySyncMerge.conflicts(first.snapshot.syncJournal!).isEmpty)
    }

    @Test func concurrentEditsKeepBothAndExplicitResolutionConverges() throws {
        let (first, second) = pair()
        var left = first.snapshot.items[0], right = second.snapshot.items[0]
        left.body = "Office version"; right.body = "Home version"
        #expect(first.save(left)); #expect(second.save(right))
        #expect(first.receiveSync(second.snapshot.syncJournal!))
        #expect(first.snapshot.items[0].body == "Office version")
        let conflict = try #require(ProductivitySyncMerge.conflicts(first.snapshot.syncJournal!).first)
        #expect(conflict.versions.count == 2)
        let home = try #require(conflict.versions.first { $0.item?.body == "Home version" })
        #expect(first.resolveSyncConflict(conflict, keeping: home, keepBoth: false))
        #expect(second.receiveSync(first.snapshot.syncJournal!))
        #expect(first.snapshot.items[0].body == "Home version")
        #expect(second.snapshot.items[0].body == "Home version")
        #expect(ProductivitySyncMerge.conflicts(second.snapshot.syncJournal!).isEmpty)
        #expect(second.snapshot.syncJournal!.contains { $0.item?.body == "Office version" })
    }

    @Test func editingVisibleConflictedVersionDoesNotDiscardOtherVersion() throws {
        let (first, second) = pair()
        var a = first.snapshot.items[0], b = second.snapshot.items[0]
        a.body = "A"; b.body = "B"
        #expect(first.save(a)); #expect(second.save(b))
        #expect(first.receiveSync(second.snapshot.syncJournal!))
        a = first.snapshot.items[0]; a.body = "A revised"
        #expect(first.save(a))
        let conflict = try #require(ProductivitySyncMerge.conflicts(first.snapshot.syncJournal!).first)
        #expect(Set(conflict.versions.compactMap { $0.item?.body }) == ["A revised", "B"])
        #expect(first.resolveSyncConflict(conflict, keeping: conflict.versions[0], keepBoth: true))
        #expect(first.snapshot.items.count == 2)
        #expect(Set(first.snapshot.items.map(\.body)) == ["A revised", "B"])
    }

    @Test func dailyFocusConflictsCanKeepAlternativesAsNotes() throws {
        let first = workspace("A"), second = workspace("B")
        let note = DailyFocusNote(id: "2026-09-08", date: .now, intention: "Start")
        #expect(first.saveDailyNote(note)); #expect(first.prepareSync())
        #expect(second.prepareSync()); #expect(second.receiveSync(first.snapshot.syncJournal!))
        var a = note, b = note; a.intention = "First plan"; b.intention = "Other plan"
        #expect(first.saveDailyNote(a)); #expect(second.saveDailyNote(b))
        #expect(first.receiveSync(second.snapshot.syncJournal!))
        let conflict = try #require(ProductivitySyncMerge.conflicts(first.snapshot.syncJournal!).first)
        #expect(first.resolveSyncConflict(conflict, keeping: conflict.versions[0], keepBoth: true))
        #expect(first.snapshot.dailyNotes.count == 1)
        #expect(first.snapshot.items.count == 1)
        #expect(first.snapshot.items[0].kind == .note)
    }

    @Test func missingParentsAndInvalidChangesNeverPartiallyApply() throws {
        let value = workspace("A")
        #expect(value.prepareSync())
        let before = value.snapshot
        let item = ProductivityItem(title: "Remote task")
        let revision = ProductivitySyncRevision(parents: [UUID()], device: "B", item: item)
        #expect(!value.receiveSync([revision]))
        #expect(value.snapshot == before)
        var invalid = revision; invalid.parents = []; invalid.item?.durationMinutes = 0
        #expect(!value.receiveSync([invalid]))
        #expect(value.snapshot == before)
    }

    @Test func corruptCyclesAndIdentifierCollisionsAreRejected() throws {
        let item = ProductivityItem(title: "Item")
        var a = ProductivitySyncRevision(device: "A", item: item)
        var b = ProductivitySyncRevision(device: "B", item: item)
        a.parents = [b.id]; b.parents = [a.id]
        #expect(throws: (any Error).self) { try ProductivitySyncMerge.union([a], [b]) }
        a.parents = []; b = a; b.item?.body = "Different payload"
        #expect(throws: (any Error).self) { try ProductivitySyncMerge.union([a], [b]) }
    }

    @Test func replayAndShuffledArrivalDoNotDuplicateItems() throws {
        let (first, second) = pair()
        var item = first.snapshot.items[0]
        for index in 0..<20 { item.body = "Revision \(index)"; #expect(first.save(item)) }
        let journal = first.snapshot.syncJournal!
        #expect(second.receiveSync(journal.reversed()))
        let saved = second.snapshot
        #expect(second.receiveSync(journal + journal))
        #expect(second.snapshot == saved)
        #expect(second.snapshot.items.count == 1)
        #expect(second.snapshot.items[0].body == "Revision 19")
    }

    @Test func archiveAndRoutineCompletionsTravelButTimersAndAlertPreferencesStayLocal() async throws {
        let (first, second) = pair()
        #expect(first.quickCapture("Stretch", kind: .exercise))
        let routine = first.snapshot.items.first { $0.kind == .exercise }!
        first.toggleComplete(routine)
        first.archive(first.snapshot.items[0])
        first.startSession(routine)
        await first.setNotificationsEnabled(true)
        #expect(second.receiveSync(first.snapshot.syncJournal!))
        #expect(second.snapshot.items.first { $0.id == routine.id }!.exerciseCompletions.count == 1)
        #expect(second.snapshot.items.first { $0.id == first.snapshot.items[0].id }!.archivedAt != nil)
        #expect(second.snapshot.session == nil)
        #expect(!second.snapshot.preferences.notificationsEnabled)
    }

    @Test func immutableFolderTransportPreservesOfflineWritersAndBackups() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let transport = ProductivitySyncTransport()
        let (first, second) = pair()
        #expect(first.quickCapture("Office addition", kind: .task))
        #expect(second.quickCapture("Home addition", kind: .task))
        let backup = ProductivityBackup(snapshot: first.snapshot, device: "Office")
        _ = try await transport.exchange(folder: folder, revisions: first.snapshot.syncJournal!, backup: backup)
        let remote = try await transport.exchange(folder: folder, revisions: second.snapshot.syncJournal!, backup: nil)
        #expect(first.receiveSync(remote))
        #expect(first.snapshot.items.count == 3)
        let backups = try await transport.backups(folder: folder)
        #expect(backups.count == 1)
        #expect(backups[0].backup.snapshot.syncJournal == nil)
        #expect(backups[0].backup.snapshot.session == nil)
        #expect(backups[0].backup.snapshot.items.count == 2)
        let count = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("Tidy Today/Changes").path).count
        _ = try await transport.exchange(folder: folder, revisions: second.snapshot.syncJournal!, backup: nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("Tidy Today/Changes").path).count == count)
    }

    @Test func backupOnlyDoesNotPublishChangesOrImportOtherMacEdits() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let transport = ProductivitySyncTransport()
        let (first, second) = pair()
        _ = try await transport.exchange(folder: folder, revisions: first.snapshot.syncJournal!, backup: nil)
        #expect(second.quickCapture("Private to this backup", kind: .note))
        let remote = try await transport.exchange(folder: folder, revisions: nil, backup: ProductivityBackup(snapshot: second.snapshot, device: "B"))
        #expect(remote.isEmpty)
        let files = try await transport.exchange(folder: folder, revisions: [], backup: nil)
        #expect(!files.contains { $0.item?.title == "Private to this backup" })
    }

    @Test func restorePreservesNewerItemsAndCreatesRecoveryBackup() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let value = workspace("A")
        #expect(value.quickCapture("Original", kind: .note))
        let backup = ProductivityBackup(snapshot: value.snapshot, device: "A")
        var item = value.snapshot.items[0]; item.title = "Edited"; #expect(value.save(item))
        #expect(value.quickCapture("Created later", kind: .task))
        let sync = ProductivitySyncService(workspace: value, directory: folder)
        #expect(await sync.restore(backup))
        #expect(Set(value.snapshot.items.map(\.title)) == ["Original", "Created later"])
        let files = try FileManager.default.contentsOfDirectory(at: folder.appendingPathComponent("Today Recovery"), includingPropertiesForKeys: nil)
        let recovery = try JSONDecoder().decode(ProductivityBackup.self, from: Data(contentsOf: files[0]))
        #expect(Set(recovery.snapshot.items.map(\.title)) == ["Edited", "Created later"])
    }

    @Test func legacyLocalFilesLoadWithoutSyncAndJournalSurvivesRestart() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProductivityStore(fileURL: folder.appendingPathComponent("productivity.json"))
        var legacy = ProductivitySnapshot(); legacy.items = [ProductivityItem(title: "Existing work")]
        try store.save(legacy)
        #expect(try store.load().syncJournal == nil)
        let value = ProductivityService(store: store, notifier: SilentProductivityNotifications())
        #expect(value.prepareSync())
        #expect(try store.load().syncJournal?.count == 1)
        #expect(try store.load().items[0].title == "Existing work")
    }
    @Test func identicalConcurrentEditsDoNotBecomeConflictsOnNextEdit() throws {
        let (first, second) = pair()
        var a = first.snapshot.items[0], b = second.snapshot.items[0]
        a.body = "Same text"; b.body = "Same text"
        #expect(first.save(a)); #expect(second.save(b))
        #expect(first.receiveSync(second.snapshot.syncJournal!))
        #expect(ProductivitySyncMerge.conflicts(first.snapshot.syncJournal!).isEmpty)
        a = first.snapshot.items[0]; a.body = "Next edit"
        #expect(first.save(a))
        #expect(second.receiveSync(first.snapshot.syncJournal!))
        #expect(ProductivitySyncMerge.conflicts(second.snapshot.syncJournal!).isEmpty)
        #expect(second.snapshot.items[0].body == "Next edit")
    }

    @Test func savedFolderReconnectsAndServiceSyncsBothDirections() async throws {
        let root = try directory(), folder = root.appendingPathComponent("Drive")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = workspace("A"), second = workspace("B")
        #expect(first.quickCapture("Sent from A", kind: .note))
        let a = ProductivitySyncService(workspace: first, directory: root.appendingPathComponent("A"))
        let b = ProductivitySyncService(workspace: second, directory: root.appendingPathComponent("B"))
        #expect(a.connect(folder: folder, mode: .twoWay)); #expect(b.connect(folder: folder, mode: .twoWay))
        await a.syncNow(); await b.syncNow()
        #expect(a.message == nil); #expect(b.message == nil)
        #expect(second.snapshot.items[0].title == "Sent from A")
        #expect(second.quickCapture("Sent from B", kind: .task))
        await b.syncNow(); await a.syncNow()
        #expect(first.snapshot.items.count == 2)
        let reopened = ProductivitySyncService(workspace: first, directory: root.appendingPathComponent("A"))
        #expect(reopened.isEnabled); #expect(reopened.mode == .twoWay)
        a.disconnect(); b.disconnect()
    }

    @Test func missingFolderRetriesWithoutReplacingLocalData() async throws {
        let root = try directory(), folder = root.appendingPathComponent("Drive")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let value = workspace("A")
        #expect(value.quickCapture("Local work", kind: .note))
        let sync = ProductivitySyncService(workspace: value, directory: root.appendingPathComponent("config"))
        #expect(sync.connect(folder: folder, mode: .twoWay))
        try FileManager.default.removeItem(at: folder)
        await sync.syncNow()
        #expect(sync.message != nil)
        #expect(value.snapshot.items[0].title == "Local work")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        await sync.syncNow()
        #expect(sync.message == nil)
        #expect(sync.lastExchange != nil)
        sync.disconnect()
    }

    @Test func malformedCloudHistoryDoesNotCreateEndlessDuplicateBackups() async throws {
        let root = try directory(), folder = root.appendingPathComponent("Drive")
        let changes = folder.appendingPathComponent("Tidy Today/Changes")
        try FileManager.default.createDirectory(at: changes, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("damaged".utf8).write(to: changes.appendingPathComponent("invalid.json"))
        let value = workspace("A")
        #expect(value.quickCapture("Keep me", kind: .note))
        let sync = ProductivitySyncService(workspace: value, directory: root.appendingPathComponent("config"))
        #expect(sync.connect(folder: folder, mode: .twoWay))
        await sync.syncNow(); await sync.syncNow(); await sync.syncNow()
        #expect(sync.message != nil)
        #expect(value.snapshot.items[0].title == "Keep me")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("Tidy Today/Backups").path).count == 1)
        sync.disconnect()
    }

    @Test func automaticBackupRunsAfterLocalEdits() async throws {
        let root = try directory(), folder = root.appendingPathComponent("Drive")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let value = workspace("A")
        let sync = ProductivitySyncService(workspace: value, directory: root.appendingPathComponent("config"))
        #expect(sync.connect(folder: folder, mode: .backup))
        #expect(value.quickCapture("Automatically saved", kind: .note))
        for _ in 0..<30 {
            if sync.lastExchange != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(sync.lastExchange != nil)
        await sync.loadBackups()
        #expect(sync.backups.first?.backup.snapshot.items.first?.title == "Automatically saved")
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("Tidy Today/Changes").path))
        sync.disconnect()
    }

}
