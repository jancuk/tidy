import Foundation

@MainActor
final class TextActionStore: ObservableObject {
    @Published private(set) var actions: [TextAction] = []
    @Published private(set) var errorMessage: String?
    private let url: URL
    private var readable = true

    struct Presets: Codable {
        var version = 1
        var actions: [TextAction]
    }

    init(directory: URL? = nil) {
        let directory = directory ?? SecureLocalStorage.applicationSupportDirectory()
        SecureLocalStorage.ensureOwnerOnlyDirectory(at: directory)
        url = directory.appendingPathComponent("text-actions.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { actions = try Self.decode(Data(contentsOf: url)) }
        catch { readable = false; errorMessage = "Could not load text actions. The original file has been preserved. \(error.localizedDescription)" }
    }

    static func decode(_ data: Data) throws -> [TextAction] {
        guard data.count <= 1_048_576 else { throw TextActionError.invalid("Preset files must be smaller than 1 MB.") }
        let presets = try JSONDecoder().decode(Presets.self, from: data)
        guard presets.version == 1, presets.actions.count <= 100 else {
            throw TextActionError.invalid("Unsupported preset version or more than 100 actions.")
        }
        var ids = Set<String>()
        for action in presets.actions {
            try validate(action)
            guard ids.insert(action.id).inserted else { throw TextActionError.invalid("The preset contains duplicate action IDs.") }
        }
        return presets.actions
    }

    static func validate(_ action: TextAction) throws {
        guard action.kind == .custom, UUID(uuidString: action.id) != nil,
              !action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              action.title.count <= 80,
              !action.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              action.instruction.count <= 8_000 else {
            throw TextActionError.invalid("Give the action a title (up to 80 characters) and instructions (up to 8,000 characters).")
        }
        if let shortcut = action.shortcut, !shortcut.isEmpty, Hotkey.validated(shortcut) == nil {
            throw TextActionError.invalid("Use a shortcut such as control+option+p, with Control or Command and one letter, digit, or space.")
        }
    }

    func save(_ action: TextAction) throws {
        try Self.validate(action)
        var next = actions
        if let index = next.firstIndex(where: { $0.id == action.id }) { next[index] = action }
        else { next.append(action) }
        try persist(next)
    }

    func remove(_ action: TextAction) throws { try persist(actions.filter { $0.id != action.id }) }

    func importPresets(_ data: Data) throws {
        let imported = try Self.decode(data).map { action in
            var copy = action
            copy.id = UUID().uuidString
            // Imported presets must not silently claim global shortcuts.
            copy.shortcut = nil
            return copy
        }
        try persist(actions + imported)
    }

    func exportPresets() throws -> Data {
        try Self.encode(actions)
    }

    private static func encode(_ actions: [TextAction]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Presets(actions: actions))
        guard data.count <= 1_048_576 else {
            throw TextActionError.invalid("The complete preset collection must fit within 1 MB. Shorten or remove some actions before adding more.")
        }
        return data
    }

    private func persist(_ next: [TextAction]) throws {
        guard readable else { throw TextActionError.invalid(errorMessage ?? "Preset storage is unavailable.") }
        guard next.count <= 100 else { throw TextActionError.invalid("Keep up to 100 custom actions.") }
        let data = try Self.encode(next)
        try data.write(to: url, options: .atomic)
        SecureLocalStorage.protectFile(at: url)
        actions = next
        errorMessage = nil
    }
}
