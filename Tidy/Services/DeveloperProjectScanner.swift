import Foundation

struct DeveloperProjectSummary: Identifiable {
    var id: String { url.path }
    let url: URL
    var size: Int64 = 0
    var artifactSize: Int64 = 0
    var artifactCount = 0
    let gitState: ProjectGitState
    var displaySize: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
}

enum ProjectGitState: String {
    case clean, changed, unavailable, notRepository
    var title: String {
        switch self {
        case .clean: "Git clean"
        case .changed: "Uncommitted changes — review carefully"
        case .unavailable: "Git status unavailable — review carefully"
        case .notRepository: "No Git repository at project root"
        }
    }
}

struct DeveloperProjectScan {
    var projects: [DeveloperProjectSummary]
    var proposals: [FileTidyProposal]
    var warnings: [String]
}

final class DeveloperProjectScanner {
    private let manager: FileManager
    private var projects: [String: DeveloperProjectSummary] = [:]
    private var proposals: [FileTidyProposal] = []
    private var warnings: [String] = []
    private var visited = 0
    private let maximumEntries = 250_000

    init(fileManager: FileManager = .default) { manager = fileManager }

    static let reviewFolder = "Tidy Project Review"
    static let generatedNames: Set<String> = ["node_modules", ".next", ".nuxt", "dist", "build", ".turbo", "coverage", "deriveddata", ".build", "target", "__pycache__", ".pytest_cache"]
    static let excludedNames: Set<String> = [".git", ".svn", ".hg", ".ssh", ".aws", ".gnupg", "Tidy Organized", "Tidy Project Review", "Build Artifacts Review", "Duplicates Review", "Large Stale Review"]

    static func isProject(_ url: URL, manager: FileManager = .default) -> Bool {
        let markers = [".git", "package.json", "Package.swift", "Cargo.toml", "pyproject.toml", "go.mod", "Gemfile", "pom.xml", "build.gradle"]
        if markers.contains(where: { manager.fileExists(atPath: url.appendingPathComponent($0).path) }) { return true }
        return (try? manager.contentsOfDirectory(atPath: url.path).contains { $0.hasSuffix(".xcodeproj") }) == true
    }

    func scan(root: URL) throws -> DeveloperProjectScan {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        projects = [:]; proposals = []; warnings = []; visited = 0
        try walk(root, owner: nil, root: root, depth: 0)
        if visited >= maximumEntries { warnings.append("Scan stopped at 250,000 entries. Sizes are partial; choose a smaller folder for a complete scan.") }
        return DeveloperProjectScan(projects: projects.values.sorted { $0.size > $1.size }, proposals: proposals, warnings: warnings)
    }

    private func walk(_ directory: URL, owner: URL?, root: URL, depth: Int) throws {
        try Task.checkCancellation()
        guard visited < maximumEntries else { return }
        guard depth <= 40 else { warnings.append("Skipped a deeply nested folder at \(directory.path); sizes are partial."); return }
        let current: URL?
        if Self.isProject(directory, manager: manager) {
            current = directory
            projects[directory.path] = DeveloperProjectSummary(url: directory, gitState: Self.gitState(at: directory))
        } else { current = owner }
        let children: [URL]
        do { children = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey, .isPackageKey]) }
        catch { warnings.append("Could not inspect \(directory.lastPathComponent); its size is incomplete."); return }

        for child in children.sorted(by: { $0.path < $1.path }) {
            try Task.checkCancellation()
            guard visited < maximumEntries else { break }
            visited += 1
            guard !Self.excludedNames.contains(child.lastPathComponent),
                  !FolderAccessPolicy.isProtectedHomeDescendant(child, selectedRoot: root),
                  let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey, .isPackageKey]),
                  values.isSymbolicLink != true else { continue }
            if values.isDirectory == true {
                if current == nil && Self.generatedNames.contains(child.lastPathComponent.lowercased()) { continue }
                if let current, Self.generatedNames.contains(child.lastPathComponent.lowercased()) || child.pathExtension == "xcarchive" {
                    let size = try measuredSize(child)
                    projects[current.path]?.size += size
                    projects[current.path]?.artifactSize += size
                    projects[current.path]?.artifactCount += 1
                    let gitState = projects[current.path]?.gitState ?? .unavailable
                    let childPath = child.resolvingSymlinksInPath().standardizedFileURL.path
                    guard childPath.hasPrefix(root.path + "/") else { continue }
                    let relative = String(childPath.dropFirst(root.path.count + 1))
                    let destination = root.appendingPathComponent(Self.reviewFolder).appendingPathComponent(relative)
                    var proposal = FileTidyProposal(id: UUID(), action: .move, category: .buildArtifacts,
                                                   sourceURL: child, destinationURL: destination, fileName: child.lastPathComponent,
                                                   size: size, reason: Self.explanation(for: child.lastPathComponent) + " " + gitState.title + ". Moving keeps the files for undo and does not free disk space.",
                                                   risk: gitState == .clean ? .review : .high,
                                                   projectHint: current.lastPathComponent, usagePattern: "Generated project files",
                                                   isRecommendedByDefault: false, duplicateOf: nil)
                    proposal.projectRootURL = current
                    proposals.append(proposal)
                } else if values.isPackage == true {
                    if let current { projects[current.path]?.size += try measuredSize(child) }
                } else {
                    try walk(child, owner: current, root: root, depth: depth + 1)
                }
            } else if values.isRegularFile == true, let current {
                projects[current.path]?.size += Int64(values.fileSize ?? 0)
            }
        }
    }

    private func measuredSize(_ url: URL) throws -> Int64 {
        guard let enumerator = manager.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey],
                                                  errorHandler: { [weak self] _, _ in self?.warnings.append("Some files in \(url.lastPathComponent) could not be measured."); return true }) else { return 0 }
        var size: Int64 = 0
        for case let file as URL in enumerator {
            try Task.checkCancellation()
            visited += 1
            guard visited < maximumEntries else { break }
            guard let values = try? file.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey]) else { continue }
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isRegularFile == true { size += Int64(values.fileSize ?? 0) }
        }
        return size
    }

    static func gitState(at root: URL) -> ProjectGitState {
        guard hasRepositoryAncestor(root) else { return .notRepository }
        guard let result = gitOutput(root: root, arguments: ["status", "--porcelain=v1", "--untracked-files=normal", "--ignore-submodules=all"]) else { return .unavailable }
        return result.isEmpty ? .clean : .changed
    }

    static func containsTrackedFiles(_ url: URL, project: URL) -> Bool? {
        let project = project.resolvingSymlinksInPath().standardizedFileURL
        let url = url.resolvingSymlinksInPath().standardizedFileURL
        guard url.path.hasPrefix(project.path + "/") else { return nil }
        guard hasRepositoryAncestor(project) else { return false }
        let relative = String(url.path.dropFirst(project.path.count + 1))
        guard let output = gitOutput(root: project, arguments: ["ls-files", "--", relative]) else { return nil }
        return !output.isEmpty
    }

    private static func hasRepositoryAncestor(_ root: URL) -> Bool {
        var directory = root.standardizedFileURL
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent(".git").path) { return true }
            directory.deleteLastPathComponent()
        }
        return false
    }

    private static func gitOutput(root: URL, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["--no-optional-locks", "--literal-pathspecs", "-c", "core.fsmonitor=false", "-C", root.path] + arguments
        var environment = ProcessInfo.processInfo.environment
        for key in environment.keys where key.hasPrefix("GIT_") { environment.removeValue(forKey: key) }
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timeout.cancel()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch { return nil }
    }

    static func explanation(for name: String) -> String {
        switch name.lowercased() {
        case "node_modules": "Installed JavaScript dependencies. Restore with the project's package manager; local dependency edits would be moved too."
        case ".next", ".nuxt", ".turbo": "Framework build cache. Moving it forces a rebuild and may interrupt a running dev server."
        case "coverage": "Test coverage reports. Regenerate by rerunning coverage tests."
        case "__pycache__", ".pytest_cache": "Python cache. It is normally regenerated when running code or tests."
        case "deriveddata", ".build": "Swift/Xcode build output. Rebuilding may require dependency downloads."
        default: "This name commonly holds generated output, but may contain hand-edited or irreplaceable files. Inspect it before moving."
        }
    }
}
