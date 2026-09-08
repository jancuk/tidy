import Foundation

enum ProductivitySyncMode: String, Codable, CaseIterable, Identifiable {
    case backup = "Automatic backup"
    case twoWay = "Two-way sync"
    var id: String { rawValue }
}

struct ProductivitySyncRevision: Codable, Equatable, Identifiable {
    var version = 1
    var id = UUID()
    var parents: [UUID] = []
    var device: String
    var createdAt = Date()
    var item: ProductivityItem?
    var dailyNote: DailyFocusNote?

    var key: String { item.map { "item/\($0.id)" } ?? "day/\(dailyNote?.id ?? "")" }
    var title: String { item?.title ?? dailyNote.map { "Focus · \($0.date.formatted(date: .abbreviated, time: .omitted))" } ?? "Untitled" }
    var detail: String {
        if let item {
            var lines = ["Type: \(item.kind.title) · Priority: \(item.priority.title)",
                         "Tags: \(item.tags.joined(separator: ", "))", "Pinned: \(item.pinned ? "Yes" : "No")",
                         "Planned: \(item.plannedDay?.formatted() ?? "None")", "Due: \(item.dueAt?.formatted() ?? "None")",
                         "Reminder: \(item.reminderEnabled ? "On" : "Off")", "Completed: \(item.completedAt?.formatted() ?? "No")",
                         "Archived: \(item.archivedAt?.formatted() ?? "No")"]
            if item.kind == .exercise {
                lines += ["Routine: \(item.cadence.rawValue) · \(item.durationMinutes) minutes · Starts \(item.routineStart.formatted()) · Weekday \(item.routineWeekday)",
                          "Sessions: \(item.exerciseCompletions.map { $0.formatted() }.joined(separator: ", "))"]
            }
            return lines.joined(separator: "\n")
        }
        return [dailyNote?.intention ?? "", dailyNote?.reflection ?? ""].joined(separator: "\n\n")
    }

    func hasSameContent(as other: Self) -> Bool {
        var left = item, right = other.item
        left?.updatedAt = .distantPast; right?.updatedAt = .distantPast
        return left == right && dailyNote == other.dailyNote
    }

    static func editingParents(_ versions: [Self], visible: [Self]) -> [UUID] {
        if let first = versions.first, versions.allSatisfy({ $0.hasSameContent(as: first) }) { return versions.map(\.id) }
        return (visible.isEmpty ? versions : visible).map(\.id)
    }

    func validate() throws {
        guard version == 1 else { throw ProductivityError.unsupportedVersion }
        guard (item == nil) != (dailyNote == nil), !parents.contains(id), Set(parents).count == parents.count else {
            throw ProductivityError.invalid("A sync change is invalid. No workspace data was replaced.")
        }
        if let item { try ProductivitySyncValidation.item(item) }
        if let dailyNote, dailyNote.id.isEmpty { throw ProductivityError.invalid("A focus note has no date identifier.") }
    }
}

struct ProductivitySyncConflict: Identifiable {
    var id: String
    var versions: [ProductivitySyncRevision]
    var title: String { versions.first?.title ?? "Workspace conflict" }
}

enum ProductivitySyncValidation {
    static func item(_ item: ProductivityItem) throws {
        guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...180).contains(item.durationMinutes), (1...7).contains(item.routineWeekday) else {
            throw ProductivityError.invalid("A workspace item has an invalid title or routine. No workspace data was replaced.")
        }
    }

    static func snapshot(_ snapshot: ProductivitySnapshot) throws {
        guard snapshot.version == 1 else { throw ProductivityError.unsupportedVersion }
        guard Set(snapshot.items.map(\.id)).count == snapshot.items.count,
              Set(snapshot.dailyNotes.map(\.id)).count == snapshot.dailyNotes.count else {
            throw ProductivityError.invalid("The workspace contains duplicate records.")
        }
        for item in snapshot.items { try self.item(item) }
        guard snapshot.dailyNotes.allSatisfy({ !$0.id.isEmpty }) else { throw ProductivityError.invalid("A focus note has no date identifier.") }
    }
}

struct ProductivityBackup: Codable, Identifiable {
    var format = "tidy-today-backup"
    var version = 1
    var id = UUID()
    var createdAt = Date()
    var device: String
    var snapshot: ProductivitySnapshot

    init(snapshot: ProductivitySnapshot, device: String) {
        self.device = device
        self.snapshot = snapshot
        self.snapshot.syncJournal = nil
        self.snapshot.preferences = ProductivityPreferences()
        self.snapshot.session = nil
    }

    func validate() throws {
        guard format == "tidy-today-backup", version == 1 else { throw ProductivityError.unsupportedVersion }
        try ProductivitySyncValidation.snapshot(snapshot)
    }
}

struct ProductivityBackupFile: Identifiable {
    var url: URL
    var backup: ProductivityBackup
    var id: UUID { backup.id }
}

enum ProductivitySyncMerge {
    static func union(_ local: [ProductivitySyncRevision], _ remote: [ProductivitySyncRevision]) throws -> [ProductivitySyncRevision] {
        var result: [UUID: ProductivitySyncRevision] = [:]
        for revision in local + remote {
            try revision.validate()
            if let existing = result[revision.id], existing != revision {
                throw ProductivityError.invalid("Two different changes have the same identifier. Sync paused to preserve both files.")
            }
            result[revision.id] = revision
        }
        for revision in result.values {
            for parentID in revision.parents {
                guard let parent = result[parentID] else {
                    throw ProductivityError.invalid("Some sync changes have not arrived yet. Tidy will retry when Drive finishes downloading them.")
                }
                guard parent.key == revision.key else { throw ProductivityError.invalid("A sync change refers to a different item.") }
            }
        }
        var remaining = result.mapValues { $0.parents.count }
        var descendants: [UUID: [UUID]] = [:]
        for revision in result.values {
            for parent in revision.parents { descendants[parent, default: []].append(revision.id) }
        }
        var ready = remaining.filter { $0.value == 0 }.map(\.key)
        var visited = 0
        while let id = ready.popLast() {
            visited += 1
            for child in descendants[id] ?? [] {
                remaining[child, default: 0] -= 1
                if remaining[child] == 0 { ready.append(child) }
            }
        }
        guard visited == result.count else { throw ProductivityError.invalid("The sync history contains a cycle.") }
        return result.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    static func heads(_ journal: [ProductivitySyncRevision]) -> [String: [ProductivitySyncRevision]] {
        let ancestors = Set(journal.flatMap(\.parents))
        return Dictionary(grouping: journal.filter { !ancestors.contains($0.id) }, by: \.key)
            .mapValues { $0.sorted { $0.id.uuidString < $1.id.uuidString } }
    }

    static func conflicts(_ journal: [ProductivitySyncRevision]) -> [ProductivitySyncConflict] {
        heads(journal).compactMap { key, versions in
            guard let first = versions.first, versions.contains(where: { !$0.hasSameContent(as: first) }) else { return nil }
            return ProductivitySyncConflict(id: key, versions: versions)
        }.sorted { $0.id < $1.id }
    }

    static func recording(_ next: ProductivitySnapshot, after old: ProductivitySnapshot, device: String) -> ProductivitySnapshot {
        var next = next
        var journal = old.syncJournal ?? []
        let heads = heads(journal)
        for item in next.items {
            let key = "item/\(item.id)"
            if old.items.first(where: { $0.id == item.id }) != item || heads[key] == nil {
                let versions = heads[key] ?? []
                let visible = versions.filter { $0.item == old.items.first(where: { $0.id == item.id }) }
                journal.append(ProductivitySyncRevision(parents: ProductivitySyncRevision.editingParents(versions, visible: visible), device: device, item: item))
            }
        }
        for note in next.dailyNotes {
            let key = "day/\(note.id)"
            if old.dailyNotes.first(where: { $0.id == note.id }) != note || heads[key] == nil {
                let versions = heads[key] ?? []
                let visible = versions.filter { $0.dailyNote == old.dailyNotes.first(where: { $0.id == note.id }) }
                journal.append(ProductivitySyncRevision(parents: ProductivitySyncRevision.editingParents(versions, visible: visible), device: device, dailyNote: note))
            }
        }
        next.syncJournal = journal
        return next
    }

    static func applying(_ remote: [ProductivitySyncRevision], to local: ProductivitySnapshot) throws -> ProductivitySnapshot {
        let journal = try union(local.syncJournal ?? [], remote)
        var next = local
        for versions in heads(journal).values {
            // Keep the currently visible version while a concurrent edit awaits review.
            let chosen = versions.first { revision in
                if let item = revision.item { return local.items.contains(item) }
                if let note = revision.dailyNote { return local.dailyNotes.contains(note) }
                return false
            } ?? versions[0]
            if let item = chosen.item {
                if let index = next.items.firstIndex(where: { $0.id == item.id }) { next.items[index] = item }
                else { next.items.append(item) }
            }
            if let note = chosen.dailyNote {
                if let index = next.dailyNotes.firstIndex(where: { $0.id == note.id }) { next.dailyNotes[index] = note }
                else { next.dailyNotes.append(note) }
            }
        }
        next.syncJournal = journal
        return next
    }
}
