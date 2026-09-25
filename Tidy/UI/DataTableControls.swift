import SwiftUI

struct DataTableControls: View {
    @EnvironmentObject private var workspace: DataWorkspaceService
    @Environment(\.dismiss) private var dismiss
    @State var options: DataTableOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Filter & sort").font(.title2.bold())
                Spacer()
                Button("Reset") { options = DataTableOptions() }
            }
            Text("Search and filter every row, then sort the matches. Export keeps these filters and this order; hidden columns are still included.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("Search all columns", text: $options.search)
                        .textFieldStyle(.roundedBorder)
                    filterControls
                    Divider()
                    sortControls
                    Divider()
                    columnControls
                }.padding(2)
            }
            if let error = workspace.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if workspace.isRunning { ProgressView().controlSize(.small) }
                Button("Apply") {
                    Task {
                        await workspace.applyTableOptions(options)
                        if workspace.errorMessage == nil { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(WorkspaceButtonStyle(prominent: true))
            }
        }
        .padding(24)
        .frame(width: 650, height: 590)
        .disabled(workspace.isRunning)
        .interactiveDismissDisabled(workspace.isRunning)
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Filters").font(.headline)
                Picker("Match", selection: $options.matchAny) {
                    Text("All conditions").tag(false)
                    Text("Any condition").tag(true)
                }.frame(width: 230)
                Spacer()
                Button("Add filter", systemImage: "plus") {
                    if let first = workspace.result.columns.first { options.filters.append(DataColumnFilter(column: first)) }
                }
            }
            ForEach($options.filters) { $filter in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        columnPicker(selection: $filter.column)
                        Picker("Condition", selection: $filter.operation) {
                            ForEach(DataFilterOperator.allCases) { Text($0.rawValue).tag($0) }
                        }.labelsHidden()
                        Button("Remove filter", systemImage: "minus.circle") {
                            options.filters.removeAll { $0.id == filter.id }
                        }.labelStyle(.iconOnly).buttonStyle(.borderless)
                    }
                    if filter.operation.needsValue {
                        HStack {
                            TextField(filter.operation.isNumeric ? "Number" : "Value", text: $filter.value)
                                .textFieldStyle(.roundedBorder)
                            if !filter.operation.isNumeric {
                                Toggle("Case sensitive", isOn: $filter.caseSensitive).toggleStyle(.checkbox)
                            }
                        }
                    }
                }
                .padding(10)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            }
            if options.filters.isEmpty { Text("No column conditions.").font(.callout).foregroundStyle(.secondary) }
        }
    }

    private var sortControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sort order").font(.headline)
                Spacer()
                Button("Add sort", systemImage: "plus") {
                    if let next = workspace.result.columns.first(where: { name in !options.sorts.contains { $0.column == name } }) {
                        options.sorts.append(DataColumnSort(column: next))
                    }
                }.disabled(options.sorts.count >= workspace.result.columns.count)
            }
            ForEach($options.sorts) { $sort in
                HStack {
                    Text("\((options.sorts.firstIndex { $0.id == sort.id } ?? 0) + 1)")
                        .foregroundStyle(.secondary).frame(width: 16)
                    columnPicker(selection: $sort.column)
                    Picker("Treat as", selection: $sort.kind) {
                        ForEach(DataSortKind.allCases) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(width: 115)
                    Picker("Direction", selection: $sort.ascending) {
                        Text("Ascending").tag(true)
                        Text("Descending").tag(false)
                    }.labelsHidden().frame(width: 125)
                    Button("Move sort earlier", systemImage: "arrow.up") {
                        if let index = options.sorts.firstIndex(where: { $0.id == sort.id }), index > 0 {
                            options.sorts.swapAt(index, index - 1)
                        }
                    }.labelStyle(.iconOnly).buttonStyle(.borderless)
                        .disabled(options.sorts.first?.id == sort.id)
                    Button("Remove sort", systemImage: "minus.circle") {
                        options.sorts.removeAll { $0.id == sort.id }
                    }.labelStyle(.iconOnly).buttonStyle(.borderless)
                }
            }
            Text("Sorts apply from top to bottom. Choose Number for numeric CSV values; blanks and invalid numbers or dates sort last. Dates use year-month-day format, optionally with a time.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var columnControls: some View {
        DisclosureGroup("Visible columns · \(workspace.result.columns.count - options.hiddenColumns.count) of \(workspace.result.columns.count)") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                ForEach(workspace.result.columns, id: \.self) { column in
                    Toggle(column, isOn: Binding(
                        get: { !options.hiddenColumns.contains(column) },
                        set: { if $0 { options.hiddenColumns.remove(column) } else { options.hiddenColumns.insert(column) } }
                    ))
                    .toggleStyle(.checkbox)
                    .disabled(!options.hiddenColumns.contains(column) && options.hiddenColumns.count == workspace.result.columns.count - 1)
                }
            }.padding(.top, 8)
        }
    }

    private func columnPicker(selection: Binding<String>) -> some View {
        Picker("Column", selection: selection) {
            ForEach(workspace.result.columns, id: \.self) { Text($0).tag($0) }
        }.labelsHidden()
    }
}
