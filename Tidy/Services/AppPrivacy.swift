import Foundation

enum AppPrivacyError: LocalizedError, Equatable {
    case localOnlyProviderRequired

    var errorDescription: String? {
        switch self {
        case .localOnlyProviderRequired:
            "Local-only AI is enabled. Choose Ollama or LanguageTool in Settings to process content without a cloud AI provider."
        }
    }
}

enum AppPrivacyPolicy {
    static var isLocalOnlyAIEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppDefaults.localOnlyAI)
    }

    static func validateAIProvider(_ provider: GrammarProviderID) throws {
        guard !isLocalOnlyAIEnabled || provider.processesContentLocally else {
            throw AppPrivacyError.localOnlyProviderRequired
        }
    }
}

extension GrammarProviderID {
    var processesContentLocally: Bool {
        switch self {
        case .ollama, .languageTool:
            true
        case .gemini, .openAI, .anthropic, .deepSeek, .openCode, .codexCLI, .claudeCLI:
            false
        }
    }
}

struct PrivacyStorageItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let fileNames: [String]
    let byteCount: Int64

    var formattedSize: String {
        guard byteCount > 0 else { return "Empty" }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

enum PrivacyDataInventory {
    static func snapshot(fileManager: FileManager = .default) -> [PrivacyStorageItem] {
        let directory = SecureLocalStorage.applicationSupportDirectory(fileManager: fileManager)
        return definitions.map { definition in
            let size = definition.fileNames.reduce(Int64(0)) { result, fileName in
                let url = directory.appendingPathComponent(fileName)
                let attributes = try? fileManager.attributesOfItem(atPath: url.path)
                return result + ((attributes?[.size] as? NSNumber)?.int64Value ?? 0)
            }
            return PrivacyStorageItem(
                id: definition.id,
                title: definition.title,
                detail: definition.detail,
                fileNames: definition.fileNames,
                byteCount: size
            )
        }
    }

    private static let definitions: [PrivacyStorageItem] = [
        PrivacyStorageItem(
            id: "clipboard",
            title: "Clipboard history",
            detail: "Copied text, source app, and timestamps",
            fileNames: ["clipboard.sqlite", "clipboard.sqlite-wal", "clipboard.sqlite-shm"],
            byteCount: 0
        ),
        PrivacyStorageItem(
            id: "corrections",
            title: "Correction history",
            detail: "Original and corrected text from recent grammar fixes",
            fileNames: ["corrections.json"],
            byteCount: 0
        ),
        PrivacyStorageItem(
            id: "ai-requests",
            title: "AI request diagnostics",
            detail: "Short request previews, provider, timing, and errors",
            fileNames: ["ai-requests.json"],
            byteCount: 0
        ),
        PrivacyStorageItem(
            id: "notifications",
            title: "Notification summaries",
            detail: "Cached summaries only; raw MCP responses are not persisted",
            fileNames: ["notification-digests.json", "notification-briefing.json"],
            byteCount: 0
        ),
        PrivacyStorageItem(
            id: "file-tidy",
            title: "File Tidy undo history",
            detail: "Original and destination paths needed to undo moves",
            fileNames: ["file-tidy-undo.json"],
            byteCount: 0
        )
    ]
}
