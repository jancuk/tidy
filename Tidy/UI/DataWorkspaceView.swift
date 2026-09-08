import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DataWorkspaceView: View {
    @EnvironmentObject private var workspace: DataWorkspaceService
    @State private var showAI = false
    @State private var showSave = false
    @State private var recipeName = ""
    @State private var question = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if workspace.sources.isEmpty {
                emptyState
            } else {
                workflowMenu
                Divider()
                HStack(spacing: 0) {
                    configurationPanel
                    Divider()
                    resultArea
                }
            }
        }
        .background(WorkspaceDesign.canvas)
        .sheet(isPresented: $showAI) { aiSheet }
        .sheet(isPresented: $showSave) { saveSheet }
    }

    private var header: some View {
        WorkspaceHeader(title: "Tidy Data", subtitle: "Your everyday data work, without the formulas.") {
            if workspace.isRunning { ProgressView().controlSize(.small) }
            Menu {
                if workspace.recipes.isEmpty { Text("Save a workflow to reuse its settings") }
                ForEach(workspace.recipes) { recipe in
                    Menu(recipe.name) {
                        Button("Load settings") { workspace.applyRecipe(recipe) }
                        Button("Delete", role: .destructive) { workspace.deleteRecipe(recipe) }
                    }
                }
            } label: {
                Label("Saved workflows", systemImage: "bookmark")
            }
            .fixedSize()
            .disabled(workspace.isRunning)
            Button(action: chooseCSVs) { Label("Add CSV", systemImage: "plus") }
                .buttonStyle(WorkspaceButtonStyle(prominent: true))
                .disabled(workspace.isRunning)
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Less spreadsheet busywork.\nMore answers.")
                        .font(.system(size: 30, weight: .bold))
                    Text("Look up values, bring exports together, and find what changed.\nChoose a job, match your columns, and preview a result you can trust.")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button(action: chooseCSVs) { Label("Choose CSV files", systemImage: "folder.badge.plus") }
                            .buttonStyle(WorkspaceButtonStyle(prominent: true))
                        Button("Try sample data") { Task { await workspace.loadSample() } }
                            .buttonStyle(WorkspaceButtonStyle())
                    }
                    .controlSize(.large)
                    .disabled(workspace.isRunning)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(DataWorkspaceMode.allCases) { mode in
                        Button {
                            workspace.changeMode(mode)
                            chooseCSVs()
                        } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                Image(systemName: mode.systemImage)
                                    .font(.system(size: 20)).foregroundStyle(Color.accentColor)
                                Text(mode.title).font(.system(size: 15, weight: .semibold))
                                Text(mode.example).font(.system(size: 12)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                            .padding(16)
                            .background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.07)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(workspace.isRunning)
                    }
                }
                Label("Local processing · Original files stay unchanged · No AI account needed", systemImage: "lock.shield")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if let error = workspace.errorMessage { errorLabel(error) }
            }
            .frame(maxWidth: 850)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }

    private var workflowMenu: some View {
        HStack(spacing: 6) {
            ForEach(DataWorkspaceMode.allCases) { mode in
                Button { workspace.changeMode(mode) } label: {
                    Label(mode.title, systemImage: mode.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(workspace.mode == mode ? Color.accentColor : Color.secondary)
                        .background(workspace.mode == mode ? Color.accentColor.opacity(0.12) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help(mode.detail)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .disabled(workspace.isRunning)
    }

    private var configurationPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(workspace.mode.title).font(.system(size: 19, weight: .bold))
                        Text(workspace.mode.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    sourceInventory
                    Divider()
                    workflowFields
                    if let problem = workspace.configurationProblem {
                        Label(problem, systemImage: "info.circle")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
            Divider()
            VStack(spacing: 10) {
                Button {
                    Task { await workspace.runWorkflow() }
                } label: {
                    Label("Preview \(workspace.mode.title.lowercased())", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WorkspaceButtonStyle(prominent: true)).controlSize(.large)
                .disabled(!workspace.canRun)
                Button {
                    recipeName = "\(workspace.mode.title) workflow"
                    showSave = true
                } label: { Label("Save workflow settings", systemImage: "bookmark") }
                    .buttonStyle(.borderless)
                    .disabled(!workspace.canRun)
                Text("Runs locally. Your files are never edited.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .frame(width: 290)
        .background(WorkspaceDesign.surface.opacity(0.45))
        .disabled(workspace.isRunning)
    }

    private var sourceInventory: some View {
        DisclosureGroup("Tables · \(workspace.sources.count)") {
            VStack(spacing: 8) {
                ForEach(workspace.sources) { source in
                    HStack(spacing: 6) {
                        Button { Task { await workspace.selectSource(source) } } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.displayName).lineLimit(1)
                                Text("\(source.rowCount.formatted()) rows · \(source.columns.count) columns")
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain).help("Preview \(source.displayName)")
                        Button { Task { await workspace.removeSource(source) } } label: {
                            Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain).help("Remove \(source.displayName)")
                    }
                }
                Button("Add another CSV…", action: chooseCSVs).buttonStyle(.borderless)
            }
            .font(.system(size: 11)).padding(.top, 8)
        }
        .font(.system(size: 12, weight: .semibold))
    }

    @ViewBuilder private var workflowFields: some View {
        if workspace.mode == .combine {
            Text("All \(workspace.sources.count) imported tables will be appended.")
                .font(.system(size: 12, weight: .medium))
            ForEach(workspace.sources) { source in
                Label(source.displayName, systemImage: "doc.text").font(.system(size: 12))
            }
            hint("Columns align by name. Missing columns become blank. A source column shows where each row came from.")
        } else {
            fieldTitle(workspace.mode == .compare ? "1 · Main table (before)" : "1 · Main table")
            sourcePicker("Main table", selection: Binding(get: { workspace.configuration.leftID }, set: { workspace.selectMain($0) }), exclude: nil)
            if workspace.mode.needsPair {
                fieldTitle(workspace.mode == .compare ? "2 · Reference table (after)" : "2 · Reference table")
                sourcePicker("Reference table", selection: Binding(get: { workspace.configuration.rightID }, set: { workspace.selectReference($0) }), exclude: workspace.configuration.leftID)
                fieldTitle("3 · Match rows using")
                columnPicker("Main column", source: workspace.mainSource, selection: $workspace.configuration.leftKey)
                Label("matches exactly", systemImage: "equal").font(.system(size: 10)).foregroundStyle(.secondary)
                columnPicker("Reference column", source: workspace.referenceSource, selection: $workspace.configuration.rightKey)
            }
            switch workspace.mode {
            case .lookup:
                fieldTitle("4 · Bring back a value")
                columnPicker("Value column", source: workspace.referenceSource, selection: $workspace.configuration.valueColumn)
                hint("Keeps every main row. The new value appears in _tidy_lookup; missing matches are flagged.")
            case .replace:
                fieldTitle("2 · Choose a column")
                columnPicker("Column", source: workspace.mainSource, selection: $workspace.configuration.valueColumn)
                fieldTitle("3 · Find and replace")
                TextField("Find this value", text: $workspace.configuration.find).textFieldStyle(.roundedBorder)
                TextField("Replace with (blank clears it)", text: $workspace.configuration.replacement).textFieldStyle(.roundedBorder)
                Toggle("Match entire cell", isOn: $workspace.configuration.exactReplacement)
                hint("Case-sensitive. Turn off entire-cell matching to replace text inside a value. Original values remain alongside the result.")
            case .join:
                fieldTitle("4 · Rows to keep")
                Picker("Join type", selection: $workspace.configuration.joinKind) {
                    ForEach(DataJoinKind.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden()
                hint("Repeated keys create one row for every matching pair. Check the result count before exporting.")
            case .compare:
                Toggle("Show differences only", isOn: $workspace.configuration.differencesOnly)
                hint("Both keys must be unique and complete. Shared column names are compared exactly; values appear side by side.")
            case .analyze:
                fieldTitle("2 · What do you need?")
                Picker("Calculation", selection: $workspace.configuration.aggregation) {
                    ForEach(DataAggregation.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden()
                if workspace.configuration.aggregation != .profile {
                    fieldTitle("3 · Group by")
                    columnPicker("Category", source: workspace.mainSource, selection: $workspace.configuration.groupColumn, allowAll: true)
                    if workspace.configuration.aggregation.needsMetric {
                        fieldTitle("4 · Numeric value")
                        columnPicker("Numeric column", source: workspace.mainSource, selection: $workspace.configuration.metricColumn)
                    }
                }
                hint("Calculations use every row, even when the preview shows only the first 250.")
            case .combine: EmptyView()
            }
        }
    }

    private var resultArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workspace.currentPlan?.title ?? workspace.selectedSource?.displayName ?? "Preview")
                        .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(workspace.status).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button { showAI = true } label: { Label("Ask AI", systemImage: "sparkles") }
                    .disabled(workspace.isRunning)
                if workspace.currentPlan != nil {
                    Button { Task { await workspace.useResultAsSource() } } label: {
                        Image(systemName: "plus.rectangle.on.rectangle")
                    }
                    .help("Use the full result as a table for another workflow")
                    .accessibilityLabel("Use result as a table")
                    .disabled(!workspace.canExport)
                }
                Button(action: exportResult) { Label("Export CSV", systemImage: "square.and.arrow.up") }
                    .disabled(!workspace.canExport)
            }.padding(16)
            if let error = workspace.errorMessage {
                errorLabel(error).padding(.horizontal, 16).padding(.bottom, 12)
            }
            if workspace.resultIsOutdated {
                Label("Settings changed. Run a new preview before exporting.", systemImage: "arrow.clockwise")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
            if let plan = workspace.currentPlan {
                VStack(alignment: .leading, spacing: 10) {
                    Text(plan.summary).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !workspace.resultCounts.isEmpty {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 16) { resultCounts }
                            VStack(alignment: .leading, spacing: 6) { resultCounts }
                        }
                    }
                    DisclosureGroup("Calculation details") {
                        Text(plan.sql).font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color.accentColor.opacity(0.045))
            }
            Divider()
            if workspace.result.columns.isEmpty {
                ContentUnavailableView("Ready when you are", systemImage: workspace.mode.systemImage,
                                       description: Text("Choose your tables and columns, then preview the result."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DataResultTable(table: workspace.result)
                Divider()
                HStack {
                    Text("\(workspace.result.totalRowCount.formatted()) rows · \(workspace.result.columns.count) columns")
                    Spacer()
                    Text("Preview: \(workspace.result.rows.count) rows · Export includes all rows")
                }
                .font(.system(size: 10)).foregroundStyle(.secondary).padding(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var resultCounts: some View {
        ForEach(workspace.resultCounts) { item in
            HStack(spacing: 5) {
                Text(item.count.formatted()).font(.system(size: 17, weight: .bold, design: .rounded))
                Text(item.label).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var saveSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save this workflow").font(.title2.bold())
            Text("Reuse the same columns and rules with your next export. Files and results are not saved; choose your tables when you return.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("Workflow name", text: $recipeName).textFieldStyle(.roundedBorder)
                .onSubmit { saveRecipe() }
            HStack {
                Button("Cancel") { showSave = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save", action: saveRecipe).buttonStyle(WorkspaceButtonStyle(prominent: true))
                    .disabled(recipeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 410)
    }

    private var aiSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Ask about your data", systemImage: "sparkles").font(.title2.bold())
                Spacer()
                Button("Done") { showAI = false }.keyboardShortcut(.cancelAction)
            }
            Text("Custom questions use your configured AI provider. Table names, column names, your question, and up to 30 result rows are sent to that provider. Calculations run locally.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(workspace.messages) { DataMessageBubble(message: $0) }
                    if let error = workspace.errorMessage { errorLabel(error) }
                }
            }.frame(minHeight: 180)
            TextField("e.g. Which regions have the highest unpaid amounts?", text: $question, axis: .vertical)
                .lineLimit(3...5).textFieldStyle(.roundedBorder)
            HStack {
                Text("AI results replace the current preview.").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if workspace.isRunning { ProgressView().controlSize(.small) }
                Button("Ask AI") {
                    let submitted = question
                    Task { await workspace.run(question: submitted) }
                }
                .buttonStyle(WorkspaceButtonStyle(prominent: true))
                .disabled(workspace.isRunning || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 560, height: 460)
    }

    private func fieldTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold))
    }
    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    private func errorLabel(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
    }
    private func sourcePicker(_ title: String, selection: Binding<UUID?>, exclude: UUID?) -> some View {
        Picker(title, selection: selection) {
            Text("Choose a table").tag(nil as UUID?)
            ForEach(workspace.sources.filter { $0.id != exclude }) { source in
                Text(source.displayName).tag(Optional(source.id))
            }
        }.labelsHidden().frame(maxWidth: .infinity)
    }
    private func columnPicker(_ title: String, source: DataSource?, selection: Binding<String>, allowAll: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                Text(allowAll ? "All rows (no grouping)" : "Choose a column").tag("")
                ForEach(source?.columns ?? []) { Text($0.name).tag($0.name) }
            }.labelsHidden().frame(maxWidth: .infinity)
        }
    }
    private func saveRecipe() {
        guard !recipeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        workspace.saveRecipe(name: recipeName)
        showSave = false
    }
    private func chooseCSVs() {
        let panel = NSOpenPanel()
        panel.title = "Add tables to Tidy Data"
        panel.prompt = "Add tables"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        Task { await workspace.addCSVs(panel.urls) }
    }
    private func exportResult() {
        let panel = NSSavePanel()
        panel.title = "Export complete result"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "tidy-\(workspace.mode.rawValue)-result.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await workspace.exportCurrentResult(to: url) }
    }
}
private struct DataResultTable: View {
    let table: DataTable
    private let columnWidth: CGFloat = 156
    private let rowHeight: CGFloat = 31

    private var columnIndices: [Int] {
        let leading = ["_tidy_key", "_tidy_status", "_tidy_lookup", "_tidy_original"].compactMap { table.columns.firstIndex(of: $0) }
        return leading + table.columns.indices.filter { !leading.contains($0) }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        rowNumberCell("#", header: true)
                        ForEach(columnIndices, id: \.self) { index in
                            tableCell(table.columns[index], header: true)
                        }
                    }

                    ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                        HStack(spacing: 0) {
                            rowNumberCell("\(index + 1)", header: false)
                            ForEach(columnIndices, id: \.self) { columnIndex in
                                tableCell(columnIndex < row.count ? row[columnIndex] ?? "NULL" : "", header: false)
                            }
                        }
                        .background(index.isMultiple(of: 2) ? Color.clear : WorkspaceDesign.surface.opacity(0.34))
                    }
                }
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
            }
            .defaultScrollAnchor(.topLeading)
            .overlay(alignment: .bottomTrailing) {
                if table.isTruncated {
                    Text("Showing \(table.rows.count) of \(table.totalRowCount.formatted()) rows")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())
                        .padding(10)
                }
            }
        }
    }

    private func tableCell(_ value: String, header: Bool) -> some View {
        Text(value)
            .font(.system(size: header ? 10 : 11, weight: header ? .semibold : .regular, design: header ? .rounded : .default))
            .foregroundStyle(header ? Color(NSColor.secondaryLabelColor) : Color(NSColor.labelColor))
            .lineLimit(1)
            .truncationMode(.tail)
            .help(value)
            .textSelection(.enabled)
            .frame(width: columnWidth, height: rowHeight, alignment: .leading)
            .padding(.horizontal, 8)
            .background(header ? WorkspaceDesign.surface : Color.clear)
            .overlay(alignment: .trailing) { Divider().opacity(0.35) }
            .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }

    private func rowNumberCell(_ value: String, header: Bool) -> some View {
        Text(value)
            .font(.system(size: 9, weight: header ? .semibold : .regular, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: 46, height: rowHeight, alignment: .trailing)
            .padding(.trailing, 8)
            .background(WorkspaceDesign.surface)
            .overlay(alignment: .trailing) { Divider().opacity(0.45) }
            .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }
}

private struct DataMessageBubble: View {
    let message: DataWorkspaceMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.role == .user ? "You" : "Tidy")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(message.role == .user ? Color.accentColor : Color.secondary)
            Text(message.text)
                .font(.system(size: 11))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            message.role == .user ? Color.accentColor.opacity(0.10) : WorkspaceDesign.surface,
            in: RoundedRectangle(cornerRadius: 9)
        )
    }
}
