import Foundation

enum FileTidyCategory: String, Codable, CaseIterable, Identifiable {
    case screenshots
    case installers
    case archives
    case documents
    case media
    case duplicates
    case largeStale
    case buildArtifacts
    case logs
    case temporaryExports
    case folders
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenshots:      "Screenshots"
        case .installers:       "Installers"
        case .archives:         "Archives"
        case .documents:        "Documents"
        case .media:            "Media"
        case .duplicates:       "Duplicates"
        case .largeStale:       "Large Stale Files"
        case .buildArtifacts:   "Build Artifacts"
        case .logs:             "Logs"
        case .temporaryExports: "Temporary Exports"
        case .folders:          "Folders"
        case .other:            "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .screenshots:      "camera.viewfinder"
        case .installers:       "externaldrive.badge.plus"
        case .archives:         "archivebox"
        case .documents:        "doc.text"
        case .media:            "photo.on.rectangle"
        case .duplicates:       "doc.on.doc"
        case .largeStale:       "clock.badge.exclamationmark"
        case .buildArtifacts:   "hammer"
        case .logs:             "list.bullet.rectangle"
        case .temporaryExports: "tray.and.arrow.down"
        case .folders:          "folder"
        case .other:            "questionmark.folder"
        }
    }
}

enum FileTidyAction: String, Codable {
    case move
    case rename
}

enum FileTidyRisk: String, Codable {
    case low
    case review
    case high

    var title: String {
        switch self {
        case .low:    "Low Risk"
        case .review: "Review"
        case .high:   "High Caution"
        }
    }
}

struct FileTidyRecord: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let name: String
    let path: String
    let size: Int64
    let createdAt: Date?
    let modifiedAt: Date?
    let isDirectory: Bool
    let category: FileTidyCategory
    let dateGroup: String
    let projectHint: String?
    let usagePattern: String
    let contentHash: String?

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

struct FileTidyProposal: Identifiable, Hashable {
    let id: UUID
    let action: FileTidyAction
    let category: FileTidyCategory
    let sourceURL: URL
    let destinationURL: URL
    let fileName: String
    let size: Int64
    let reason: String
    let risk: FileTidyRisk
    let projectHint: String?
    let usagePattern: String
    let isRecommendedByDefault: Bool
    let duplicateOf: URL?

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var sourcePath: String { sourceURL.path }
    var destinationPath: String { destinationURL.path }
}

struct FileTidyGroupSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let count: Int
    let size: Int64

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

struct FileTidyScanResult {
    let rootURL: URL
    let scannedAt: Date
    let records: [FileTidyRecord]
    let proposals: [FileTidyProposal]
    let typeGroups: [FileTidyGroupSummary]
    let dateGroups: [FileTidyGroupSummary]
    let projectGroups: [FileTidyGroupSummary]
    let usageGroups: [FileTidyGroupSummary]

    var totalSize: Int64 {
        records.reduce(0) { $0 + $1.size }
    }
}

struct FileTidyAppliedMove: Codable, Identifiable, Hashable {
    let id: UUID
    let action: FileTidyAction
    let sourcePath: String
    let destinationPath: String
    let finalDestinationPath: String
    let fileName: String
    let movedAt: Date
}

struct FileTidyUndoSession: Codable, Identifiable, Hashable {
    let id: UUID
    let rootPath: String
    let createdAt: Date
    let moves: [FileTidyAppliedMove]

    var moveCount: Int { moves.count }
}
