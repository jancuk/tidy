import AppKit
import SwiftUI

struct DataResultTable: NSViewRepresentable {
    let table: DataTable
    let revision: Int
    let offset: Int
    let options: DataTableOptions
    let onSort: (String, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        let grid = CopyableDataTable()
        context.coordinator.grid = grid
        grid.delegate = context.coordinator
        grid.dataSource = context.coordinator
        grid.rowHeight = 27
        grid.usesAlternatingRowBackgroundColors = true
        grid.gridStyleMask = [.solidVerticalGridLineMask, .solidHorizontalGridLineMask]
        grid.gridColor = .separatorColor.withAlphaComponent(0.3)
        grid.allowsMultipleSelection = true
        grid.allowsColumnReordering = true
        grid.allowsColumnResizing = true
        grid.columnAutoresizingStyle = .noColumnAutoresizing
        grid.menu = NSMenu()
        grid.menu?.delegate = context.coordinator
        scroll.documentView = grid
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let grid = scroll.documentView as? CopyableDataTable else { return }
        let coordinator = context.coordinator
        coordinator.onSort = onSort
        guard coordinator.revision != revision else { return }
        let leading = ["_tidy_key", "_tidy_status", "_tidy_lookup", "_tidy_original"].filter { table.columns.contains($0) }
        let columns = (leading + table.columns.filter { !leading.contains($0) })
            .filter { !options.hiddenColumns.contains($0) }
        let schemaChanged = coordinator.table.columns != table.columns
        coordinator.columnIndices = Dictionary(uniqueKeysWithValues: table.columns.enumerated().map { ($0.element, $0.offset) })
        coordinator.table = table
        coordinator.offset = offset
        coordinator.revision = revision
        let names = ["#"] + columns
        let identifiers = ["row-number"] + columns.map { "column-" + $0 }
        if schemaChanged || Set(grid.tableColumns.map { $0.identifier.rawValue }) != Set(identifiers) {
            let widths = Dictionary(uniqueKeysWithValues: grid.tableColumns.map { ($0.identifier.rawValue, $0.width) })
            for column in grid.tableColumns { grid.removeTableColumn(column) }
            for (index, identifier) in identifiers.enumerated() {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
                column.title = names[index]
                column.width = widths[identifier] ?? (index == 0 ? 65 : 170)
                column.minWidth = index == 0 ? 50 : 70
                column.maxWidth = 1000
                grid.addTableColumn(column)
            }
        }
        for column in grid.tableColumns {
            guard let name = coordinator.columnName(column) else { continue }
            if let index = options.sorts.firstIndex(where: { $0.column == name }) {
                column.title = name + (options.sorts[index].ascending ? " ↑" : " ↓") + (options.sorts.count > 1 ? " \(index + 1)" : "")
            } else { column.title = name }
        }
        grid.copyText = { [weak grid, weak coordinator] cellOnly in
            guard let grid, let coordinator else { return nil }
            let rows = cellOnly && grid.clickedRow >= 0 ? IndexSet(integer: grid.clickedRow) : grid.selectedRowIndexes
            let columns = cellOnly && grid.clickedColumn >= 0 ? [grid.tableColumns[grid.clickedColumn]] : grid.tableColumns.filter { coordinator.columnName($0) != nil }
            return rows.map { row in
                columns.map { coordinator.value(row: row, column: $0) }.joined(separator: "\t")
            }.joined(separator: "\n")
        }
        grid.deselectAll(nil)
        grid.reloadData()
        scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        weak var grid: NSTableView?
        var columnIndices: [String: Int] = [:]
        var table = DataTable.empty
        var offset = 0
        var revision = -1
        var onSort: ((String, Bool) -> Void)?

        func numberOfRows(in tableView: NSTableView) -> Int { table.rows.count }

        func columnName(_ column: NSTableColumn) -> String? {
            let identifier = column.identifier.rawValue
            return identifier.hasPrefix("column-") ? String(identifier.dropFirst(7)) : nil
        }

        func value(row: Int, column: NSTableColumn) -> String {
            guard table.rows.indices.contains(row) else { return "" }
            guard let name = columnName(column) else { return (offset + row + 1).formatted() }
            guard let index = columnIndices[name], table.rows[row].indices.contains(index) else { return "" }
            return table.rows[row][index] ?? ""
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("data-cell")
            let field = (tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField) ?? NSTextField(labelWithString: "")
            field.identifier = identifier
            field.font = .systemFont(ofSize: 11)
            field.lineBreakMode = .byTruncatingTail
            field.maximumNumberOfLines = 1
            let text = value(row: row, column: tableColumn)
            field.stringValue = String(text.prefix(2_000))
            field.toolTip = String(text.prefix(10_000))
            field.textColor = columnName(tableColumn) == nil ? .secondaryLabelColor : .labelColor
            return field
        }

        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            guard let column = columnName(tableColumn) else { return }
            onSort?(column, NSEvent.modifierFlags.contains(.shift))
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            menu.addItem(withTitle: "Copy cell", action: #selector(CopyableDataTable.copyCell(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Copy selected rows", action: #selector(CopyableDataTable.copy(_:)), keyEquivalent: "")
            for item in menu.items { item.target = grid }
        }
    }
}

private final class CopyableDataTable: NSTableView {
    var copyText: ((Bool) -> String?)?

    @objc func copy(_ sender: Any?) { copyValue(cellOnly: false) }
    @objc func copyCell(_ sender: Any?) { copyValue(cellOnly: true) }

    private func copyValue(cellOnly: Bool) {
        guard let text = copyText?(cellOnly), !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
