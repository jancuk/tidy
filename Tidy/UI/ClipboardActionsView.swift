import SwiftUI

struct ClipboardFiltersView: View {
    @ObservedObject var service: ClipboardService
    var body: some View {
        HStack {
            Toggle("Favorites", isOn: $service.pinnedOnly).toggleStyle(.button)
            Picker("Collection", selection: $service.selectedCollection) {
                Text("All collections").tag(String?.none)
                ForEach(service.collections, id: \.self) { Text($0).tag(Optional($0)) }
            }.labelsHidden()
        }.font(.caption)
    }
}

struct ClipboardEntryActions: View {
    let entry: ClipboardEntry
    @ObservedObject var service: ClipboardService
    let transform: (String?) -> Void
    let capture: (ProductivityKind) -> Void
    @State private var collection = ""
    @State private var showCollection = false

    var body: some View {
        Menu {
            Button(entry.isPinned ? "Unpin favorite" : "Pin favorite") { service.togglePin(entry) }
            Menu("Collection") {
                ForEach(service.collections, id: \.self) { name in
                    Button(name) { service.organize(entry, collection: name) }
                }
                Button("New collection…") { collection = entry.collection; showCollection = true }
                if !entry.collection.isEmpty { Button("Remove from collection") { service.organize(entry, collection: "") } }
            }
            Divider()
            Button("Text actions…") { transform(nil) }
            Button("Format JSON") { transform("json") }
            Button("Extract links") { transform("links") }
            Button("Rewrite…") { transform("tone") }
            Divider()
            Button("Save as task in Today") { capture(.task) }
            Button("Save as note in Today") { capture(.note) }
        } label: { Label("Actions", systemImage: "ellipsis.circle") }
        .fixedSize()
        .alert("Favorite collection", isPresented: $showCollection) {
            TextField("Collection name", text: $collection)
            Button("Cancel", role: .cancel) { }
            Button("Save") { service.organize(entry, collection: collection) }
        } message: { Text("Items in a collection are pinned and kept until you unpin or delete them.") }
    }
}
