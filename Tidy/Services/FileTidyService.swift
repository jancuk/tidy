import CryptoKit
import Foundation

enum FileTidyError: LocalizedError {
    case folderMissing
    case moveFailed(String)
    case undoBlocked(String)

    var errorDescription: String? {
        switch self {
        case .folderMissing:
            "Choose a folder to scan."
        case .moveFailed(let message):
            message
        case .undoBlocked(let message):
            message
        }
    }
}

struct FileTidyScanOptions {
    var largeFileThreshold: Int64 = 100 * 1_024 * 1_024
    var staleAfterDays: Int = 90
}

final class FileTidyService {
    private let fileManager: FileManager
    private let options: FileTidyScanOptions

    init(fileManager: FileManager = .default, options: FileTidyScanOptions = FileTidyScanOptions()) {
        self.fileManager = fileManager
        self.options = options
    }

    func scan(rootURL: URL) throws -> FileTidyScanResult {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw FileTidyError.folderMissing
        }

        let children = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        let records = try children
            .filter { $0.lastPathComponent != ".DS_Store" }
            .map { try record(for: $0) }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        let proposals = buildProposals(for: records, rootURL: rootURL)

        return FileTidyScanResult(
            rootURL: rootURL,
            scannedAt: Date(),
            records: records,
            proposals: proposals,
            typeGroups: groups(records, by: { $0.category.title }),
            dateGroups: groups(records, by: { $0.dateGroup }),
            projectGroups: groups(records, by: { $0.projectHint ?? "No project hint" }),
            usageGroups: groups(records, by: { $0.usagePattern })
        )
    }

    func apply(_ proposals: [FileTidyProposal], rootURL: URL) throws -> [FileTidyAppliedMove] {
        var applied: [FileTidyAppliedMove] = []

        for proposal in proposals {
            guard isContained(proposal.sourceURL, in: rootURL),
                  isContained(proposal.destinationURL, in: rootURL) else {
                throw FileTidyError.moveFailed(
                    "Refusing to move \(proposal.fileName) outside the selected folder."
                )
            }
            guard fileManager.fileExists(atPath: proposal.sourcePath) else { continue }
            do {
                let finalDestination = uniqueDestination(for: proposal.destinationURL)
                guard isContained(finalDestination, in: rootURL) else {
                    throw FileTidyError.moveFailed(
                        "Refusing to move \(proposal.fileName) outside the selected folder."
                    )
                }
                try fileManager.createDirectory(
                    at: finalDestination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.moveItem(at: proposal.sourceURL, to: finalDestination)
                applied.append(FileTidyAppliedMove(
                    id: proposal.id,
                    action: proposal.action,
                    sourcePath: proposal.sourcePath,
                    destinationPath: proposal.destinationPath,
                    finalDestinationPath: finalDestination.path,
                    fileName: proposal.fileName,
                    movedAt: Date()
                ))
            } catch {
                throw FileTidyError.moveFailed("Could not move \(proposal.fileName): \(error.localizedDescription)")
            }
        }

        return applied
    }

    func undo(_ session: FileTidyUndoSession) throws {
        let rootURL = URL(fileURLWithPath: session.rootPath, isDirectory: true)
        for move in session.moves.reversed() {
            let currentURL = URL(fileURLWithPath: move.finalDestinationPath)
            let originalURL = URL(fileURLWithPath: move.sourcePath)

            guard isContained(currentURL, in: rootURL),
                  isContained(originalURL, in: rootURL) else {
                throw FileTidyError.undoBlocked(
                    "Cannot undo \(move.fileName) because its path is outside the original folder."
                )
            }
            guard fileManager.fileExists(atPath: currentURL.path) else { continue }
            guard !fileManager.fileExists(atPath: originalURL.path) else {
                throw FileTidyError.undoBlocked("Cannot undo \(move.fileName) because the original path is occupied.")
            }

            do {
                try fileManager.createDirectory(
                    at: originalURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.moveItem(at: currentURL, to: originalURL)
            } catch {
                throw FileTidyError.undoBlocked("Could not undo \(move.fileName): \(error.localizedDescription)")
            }
        }
    }

    private var resourceKeys: [URLResourceKey] {
        [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .creationDateKey,
            .contentModificationDateKey
        ]
    }

    private func record(for url: URL) throws -> FileTidyRecord {
        let values = try url.resourceValues(forKeys: Set(resourceKeys))
        let isDirectory = values.isDirectory == true
        let size = isDirectory ? directorySize(url) : Int64(values.fileSize ?? values.totalFileAllocatedSize ?? 0)
        let category = category(for: url, isDirectory: isDirectory)
        let modifiedAt = values.contentModificationDate

        return FileTidyRecord(
            id: UUID(),
            url: url,
            name: url.lastPathComponent,
            path: url.path,
            size: size,
            createdAt: values.creationDate,
            modifiedAt: modifiedAt,
            isDirectory: isDirectory,
            category: category,
            dateGroup: dateGroup(for: modifiedAt ?? values.creationDate),
            projectHint: projectHint(for: url, isDirectory: isDirectory),
            usagePattern: usagePattern(for: url, category: category, isDirectory: isDirectory),
            contentHash: isDirectory ? nil : fileHash(url)
        )
    }

    private func buildProposals(for records: [FileTidyRecord], rootURL: URL) -> [FileTidyProposal] {
        var proposals = records.compactMap { proposal(for: $0, rootURL: rootURL) }
        proposals.append(contentsOf: duplicateProposals(for: records, rootURL: rootURL))
        return proposals.sorted { lhs, rhs in
            if lhs.risk.rawValue != rhs.risk.rawValue {
                return lhs.risk.rawValue < rhs.risk.rawValue
            }
            return lhs.fileName.localizedStandardCompare(rhs.fileName) == .orderedAscending
        }
    }

    private func proposal(for record: FileTidyRecord, rootURL: URL) -> FileTidyProposal? {
        if record.isDirectory, isBuildArtifact(record.url) {
            return proposal(
                for: record,
                category: .buildArtifacts,
                destinationFolder: rootURL.appendingPathComponent("Build Artifacts Review", isDirectory: true),
                reason: "Looks like generated developer output.",
                risk: .high,
                selected: false
            )
        }

        if isLargeAndStale(record) {
            return proposal(
                for: record,
                category: .largeStale,
                destinationFolder: rootURL.appendingPathComponent("Large Stale Review", isDirectory: true),
                reason: "Large file that has not changed in more than \(options.staleAfterDays) days.",
                risk: .review,
                selected: false
            )
        }

        switch record.category {
        case .screenshots:
            return proposal(
                for: record,
                category: .screenshots,
                destinationFolder: organizedFolder(in: rootURL, path: "Screenshots"),
                reason: "Screenshot-style name or image capture.",
                risk: .low,
                selected: true
            )
        case .installers:
            return proposal(
                for: record,
                category: .installers,
                destinationFolder: organizedFolder(in: rootURL, path: "Installers"),
                reason: "Installer package or disk image.",
                risk: .low,
                selected: true
            )
        case .archives:
            return proposal(
                for: record,
                category: .archives,
                destinationFolder: rootURL.appendingPathComponent("Archives", isDirectory: true),
                reason: "Compressed archive.",
                risk: .low,
                selected: true
            )
        case .documents:
            return proposal(
                for: record,
                category: .documents,
                destinationFolder: documentsFolder(for: record.url, rootURL: rootURL),
                reason: "Document that fits a standard Documents subfolder.",
                risk: .low,
                selected: true
            )
        case .logs:
            return proposal(
                for: record,
                category: .logs,
                destinationFolder: rootURL.appendingPathComponent("Logs", isDirectory: true),
                reason: "Log file likely safe to review away from the main folder.",
                risk: .review,
                selected: false
            )
        case .temporaryExports:
            return proposal(
                for: record,
                category: .temporaryExports,
                destinationFolder: rootURL.appendingPathComponent("Temporary Exports", isDirectory: true),
                reason: "Name suggests an export, final, copy, or temporary file.",
                risk: .review,
                selected: false
            )
        default:
            return nil
        }
    }

    private func duplicateProposals(for records: [FileTidyRecord], rootURL: URL) -> [FileTidyProposal] {
        let duplicateGroups = Dictionary(grouping: records.filter {
            !$0.isDirectory && $0.size > 0 && $0.contentHash != nil
        }, by: { "\($0.size)-\($0.contentHash ?? "")" })

        return duplicateGroups.values.flatMap { group -> [FileTidyProposal] in
            guard group.count > 1 else { return [] }
            let sorted = group.sorted {
                ($0.modifiedAt ?? .distantFuture) < ($1.modifiedAt ?? .distantFuture)
            }
            guard let original = sorted.first else { return [] }
            return sorted.dropFirst().map { record in
                proposal(
                    for: record,
                    category: .duplicates,
                    destinationFolder: rootURL.appendingPathComponent("Duplicates Review", isDirectory: true),
                    reason: "Same size and SHA-256 hash as \(original.name).",
                    risk: .review,
                    selected: false,
                    duplicateOf: original.url
                )
            }
        }
    }

    private func proposal(
        for record: FileTidyRecord,
        category: FileTidyCategory,
        destinationFolder: URL,
        reason: String,
        risk: FileTidyRisk,
        selected: Bool,
        duplicateOf: URL? = nil
    ) -> FileTidyProposal {
        FileTidyProposal(
            id: UUID(),
            action: .move,
            category: category,
            sourceURL: record.url,
            destinationURL: destinationFolder.appendingPathComponent(record.name, isDirectory: record.isDirectory),
            fileName: record.name,
            size: record.size,
            reason: reason,
            risk: risk,
            projectHint: record.projectHint,
            usagePattern: record.usagePattern,
            isRecommendedByDefault: selected,
            duplicateOf: duplicateOf
        )
    }

    private func category(for url: URL, isDirectory: Bool) -> FileTidyCategory {
        if isDirectory {
            return isBuildArtifact(url) ? .buildArtifacts : .folders
        }

        let name = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()

        if isScreenshotName(name), imageExtensions.contains(ext) { return .screenshots }
        if installerExtensions.contains(ext) { return .installers }
        if archiveExtensions.contains(ext) || archiveNames.contains(where: { name.hasSuffix($0) }) { return .archives }
        if documentExtensions.contains(ext) { return .documents }
        if mediaExtensions.contains(ext) { return .media }
        if ext == "log" || name.hasSuffix(".log.txt") { return .logs }
        if isTemporaryExportName(name) { return .temporaryExports }
        return .other
    }

    private func usagePattern(for url: URL, category: FileTidyCategory, isDirectory: Bool) -> String {
        if isDirectory && isBuildArtifact(url) { return "Generated build output" }
        return switch category {
        case .screenshots:      "Captured screen"
        case .installers:       "Downloaded installer"
        case .archives:         "Compressed package"
        case .documents:        "Readable document"
        case .media:            "Media asset"
        case .buildArtifacts:   "Generated build output"
        case .logs:             "Runtime log"
        case .temporaryExports: "Temporary export"
        case .folders:          "Folder"
        case .duplicates:       "Duplicate content"
        case .largeStale:       "Large stale item"
        case .other:            "Unclassified"
        }
    }

    private func projectHint(for url: URL, isDirectory: Bool) -> String? {
        if isDirectory {
            let markerNames = ["package.json", "Package.swift", "Cargo.toml", "pyproject.toml", ".git", "xcodeproj"]
            for marker in markerNames {
                if marker == "xcodeproj" {
                    if let children = try? fileManager.contentsOfDirectory(atPath: url.path),
                       children.contains(where: { $0.hasSuffix(".xcodeproj") }) {
                        return url.lastPathComponent
                    }
                } else if fileManager.fileExists(atPath: url.appendingPathComponent(marker).path) {
                    return url.lastPathComponent
                }
            }
        }

        let name = url.deletingPathExtension().lastPathComponent
        let separators = CharacterSet(charactersIn: "-_ .")
        let parts = name.components(separatedBy: separators).filter { $0.count >= 3 }
        guard let first = parts.first else { return nil }
        let ignored = ["screenshot", "screen", "shot", "copy", "final", "export", "image", "document"]
        return ignored.contains(first.lowercased()) ? nil : first
    }

    private func dateGroup(for date: Date?) -> String {
        guard let date else { return "Unknown date" }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        return switch days {
        case ..<1:    "Today"
        case 1..<8:   "This Week"
        case 8..<31:  "This Month"
        case 31..<91: "Last 90 Days"
        default:      "Older"
        }
    }

    private func isLargeAndStale(_ record: FileTidyRecord) -> Bool {
        guard record.size >= options.largeFileThreshold,
              let date = record.modifiedAt ?? record.createdAt,
              let cutoff = Calendar.current.date(byAdding: .day, value: -options.staleAfterDays, to: Date()) else {
            return false
        }
        return date < cutoff
    }

    private func isScreenshotName(_ name: String) -> Bool {
        name.contains("screenshot") ||
        name.contains("screen shot") ||
        name.contains("screen-shot") ||
        name.contains("clean shot") ||
        name.contains("cleanshot")
    }

    private func isTemporaryExportName(_ name: String) -> Bool {
        name.contains("export") ||
        name.contains("final") ||
        name.contains("copy") ||
        name.contains("untitled") ||
        name.contains("tmp") ||
        name.contains("temp")
    }

    private func isBuildArtifact(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return buildArtifactNames.contains(name) || name.hasSuffix(".xcarchive")
    }

    private func documentsFolder(for url: URL, rootURL: URL) -> URL {
        let category = switch url.pathExtension.lowercased() {
        case "pdf":
            "PDFs"
        case "xls", "xlsx", "csv", "tsv", "numbers":
            "Spreadsheets"
        case "ppt", "pptx", "key":
            "Presentations"
        default:
            "Other Documents"
        }
        return organizedFolder(in: rootURL, path: "Documents/\(category)")
    }

    private func organizedFolder(in rootURL: URL, path: String) -> URL {
        path.split(separator: "/").reduce(
            rootURL.appendingPathComponent("Tidy Organized", isDirectory: true)
        ) { url, component in
            url.appendingPathComponent(String(component), isDirectory: true)
        }
    }

    private func uniqueDestination(for url: URL) -> URL {
        guard fileManager.fileExists(atPath: url.path) else { return url }

        let directory = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        for index in 2...999 {
            let candidateName = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return directory.appendingPathComponent("\(base) \(UUID().uuidString).\(ext)")
    }

    private func isContained(_ candidate: URL, in rootURL: URL) -> Bool {
        let rootPath = canonicalPath(for: rootURL)
        let candidatePath = canonicalPath(for: candidate)
        return candidatePath != rootPath
            && candidatePath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    }

    private func canonicalPath(for url: URL) -> String {
        var existingAncestor = url.standardizedFileURL
        var missingComponents: [String] = []

        while !fileManager.fileExists(atPath: existingAncestor.path),
              existingAncestor.path != "/" {
            missingComponents.insert(existingAncestor.lastPathComponent, at: 0)
            existingAncestor.deleteLastPathComponent()
        }

        var canonicalURL = existingAncestor.resolvingSymlinksInPath()
        for component in missingComponents {
            canonicalURL.appendPathComponent(component)
        }
        return canonicalURL.standardizedFileURL.path
    }

    private func fileHash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: 1_048_576)
            guard !data.isEmpty else { return false }
            hasher.update(data: data)
            return true
        }) {}

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return 0
        }

        return enumerator.reduce(Int64(0)) { total, item in
            guard let fileURL = item as? URL,
                  let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey]),
                  values.isRegularFile == true else {
                return total
            }
            return total + Int64(values.fileSize ?? values.totalFileAllocatedSize ?? 0)
        }
    }

    private func groups(_ records: [FileTidyRecord], by key: (FileTidyRecord) -> String) -> [FileTidyGroupSummary] {
        Dictionary(grouping: records, by: key).map { title, items in
            FileTidyGroupSummary(
                id: title,
                title: title,
                count: items.count,
                size: items.reduce(0) { $0 + $1.size }
            )
        }
        .sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "tiff", "webp"]
    private let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg"]
    private let archiveExtensions: Set<String> = ["zip", "rar", "7z", "gz", "bz2", "xz"]
    private let archiveNames = [".tar.gz", ".tar.bz2", ".tar.xz", ".tgz"]
    private let documentExtensions: Set<String> = ["pdf", "doc", "docx", "pages", "txt", "rtf", "md", "xls", "xlsx", "csv", "tsv", "numbers", "ppt", "pptx", "key"]
    private let mediaExtensions: Set<String> = ["mov", "mp4", "m4v", "mp3", "wav", "aiff", "psd", "sketch", "fig"]
    private let buildArtifactNames: Set<String> = ["node_modules", ".next", "dist", "build", ".turbo", "coverage", "deriveddata", ".build", "target"]
}
