import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TextActionSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: TextActionStore
    @State private var editing: TextAction?
    @State private var error: String?
    @State private var imported: [TextAction] = []
    @State private var importData: Data?
    @State private var showImport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Custom text actions").font(.title2.bold())
            Text("Save instructions for selected text. Open the palette with Control–Option–Space, choose an action, and review its result. Presets contain instructions only; your text and API keys are never exported.")
                .foregroundStyle(.secondary)
            HStack {
                Button("New action") { editing = TextAction(id: UUID().uuidString, title: "", kind: .custom, instruction: "") }
                Menu("Examples") {
                    ForEach(TextAction.examples) { action in
                        Button(action.title) { var copy = action; copy.id = UUID().uuidString; editing = copy }
                    }
                }
                Spacer()
                Button("Import…") { chooseImport() }
                Button("Export…") { export() }.disabled(store.actions.isEmpty)
            }
            ForEach(store.actions) { action in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(action.title).font(.headline)
                        Spacer()
                        if let shortcut = action.shortcut { Text(shortcut).font(.caption).foregroundStyle(.secondary) }
                        Button("Edit") { editing = action }
                        Button("Delete", role: .destructive) { do { try store.remove(action) } catch { self.error = error.localizedDescription } }
                    }
                    Text(action.instruction).font(.callout).foregroundStyle(.secondary).lineLimit(4)
                }.padding(16).background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            if store.actions.isEmpty { Text("Create an action or start with an example above.").foregroundStyle(.secondary) }
            if let error = error ?? store.errorMessage ?? appState.hotkeyError { Text(error).foregroundStyle(.red) }
        }
        .sheet(item: $editing) { action in
            TextActionEditor(action: action, store: store).environmentObject(appState)
        }
        .sheet(isPresented: $showImport) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Review imported actions").font(.title2)
                Text("Import adds new presets without replacing existing ones. Global shortcuts are removed from imported presets.").foregroundStyle(.secondary)
                List(imported) { action in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(action.title).font(.headline)
                        Text(action.instruction).textSelection(.enabled)
                    }.padding(.vertical, 6)
                }
                HStack {
                    Button("Cancel") { showImport = false }
                    Spacer()
                    Button("Import \(imported.count) actions") {
                        do { if let importData { try store.importPresets(importData) }; showImport = false }
                        catch { self.error = error.localizedDescription; showImport = false }
                    }.buttonStyle(.borderedProminent)
                }
            }.padding(24).frame(width: 600, height: 470)
        }
    }

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 1_048_576 else { throw TextActionError.invalid("Preset files must be smaller than 1 MB.") }
            let data = try Data(contentsOf: url)
            imported = try TextActionStore.decode(data)
            importData = data
            error = nil
            showImport = true
        } catch { self.error = error.localizedDescription }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Tidy Text Actions.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.exportPresets().write(to: url, options: .atomic); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

private struct TextActionEditor: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State var action: TextAction
    let store: TextActionStore
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Text action").font(.title2)
            TextField("Title", text: $action.title).textFieldStyle(.roundedBorder)
            Text("Describe how to transform the selected text. Tidy supplies the text separately.").font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $action.instruction).font(.body).accessibilityLabel("Action instructions")
            TextField("Optional shortcut, e.g. control+option+p", text: Binding(get: { action.shortcut ?? "" }, set: { action.shortcut = $0.isEmpty ? nil : $0 }))
                .textFieldStyle(.roundedBorder)
            Text("A shortcut opens this action with your selection. Run it to preview the result.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save action") {
                    do {
                        try TextActionStore.validate(action)
                        try appState.validateActionShortcut(action)
                        try store.save(action)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut("s", modifiers: .command)
            }
        }.padding(24).frame(width: 580, height: 440)
    }
}
