import AppKit

struct PasteboardSnapshot {
    private let items: [SnapshotItem]

    init(pasteboard: NSPasteboard = .general) {
        items = pasteboard.pasteboardItems?.map(SnapshotItem.init) ?? []
    }

    func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        let restoredItems = items.map { item -> NSPasteboardItem in
            let pasteboardItem = NSPasteboardItem()
            for (type, data) in item.values {
                pasteboardItem.setData(data, forType: type)
            }
            return pasteboardItem
        }
        pasteboard.writeObjects(restoredItems)
    }

    private struct SnapshotItem {
        let values: [(NSPasteboard.PasteboardType, Data)]

        init(item: NSPasteboardItem) {
            values = item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
        }
    }
}
