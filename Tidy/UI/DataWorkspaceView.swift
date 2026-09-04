import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DataWorkspaceView: View {
    @EnvironmentObject private var workspace: DataWorkspaceService
    @State private var question = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.55)
            if workspace.sources.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    sourceSidebar
                    Divider().opacity(0.55)
                    resultArea
                    Divider().opacity(0.55)
                    askPanel
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Tidy Data")
                    .font(.system(size: 20, weight: .bold))
                Text("Analyze, combine, and compare CSV files locally.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Mode", selection: Binding(
                get: { workspace.mode },
                set: { workspace.changeMode($0) }
            )) {
                ForEach(DataWorkspaceMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 430)

            Button {
                chooseCSVs()
            } label: {
                Label("Add CSV", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.accentColor.opacity(0.11))
                    .frame(width: 88, height: 88)
                Image(systemName: "tablecells.badge.ellipsis")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 7) {
                Text("Bring your CSV data into Tidy")
                    .font(.system(size: 22, weight: .bold))
                Text("CSV contents stay local while DuckDB performs the calculations.\nTidy sends schema metadata and a limited result preview to your configured AI to plan and explain answers.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            HStack(spacing: 12) {
                ForEach(DataWorkspaceMode.allCases) { mode in
                    modeCard(mode)
                }
            }
            .frame(maxWidth: 740)

            Button {
                chooseCSVs()
            } label: {
                Label("Choose CSV Files", systemImage: "folder.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
        .padding(30)
    }

    private func modeCard(_ mode: DataWorkspaceMode) -> some View {
        Button {
            workspace.changeMode(mode)
            chooseCSVs()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text(mode.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(NSColor.labelColor))
                Text(mode.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(Color(NSColor.separatorColor).opacity(0.65), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    private var sourceSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SOURCES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(workspace.sources.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(workspace.sources) { source in
                        sourceRow(source)
                    }
                }
                .padding(.horizontal, 8)
            }

            Divider().opacity(0.45)
            VStack(alignment: .leading, spacing: 8) {
                if workspace.mode == .compare && workspace.sources.count >= 2 {
                    Text("MATCH ROWS USING")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Picker("Comparison key", selection: $workspace.comparisonKey) {
                        ForEach(workspace.comparisonColumns, id: \.self) { column in
                            Text(column).tag(column)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                Button {
                    chooseCSVs()
                } label: {
                    Label("Add another CSV", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
            }
            .padding(12)
        }
        .frame(width: 230)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
    }

    private func sourceRow(_ source: DataSource) -> some View {
        let selected = workspace.selectedSourceID == source.id
        return HStack(spacing: 9) {
            Button {
                Task { await workspace.selectSource(source) }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.displayName)
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.accentColor : Color(NSColor.labelColor))
                            .lineLimit(1)
                        Text("\(source.rowCount.formatted()) rows · \(source.columns.count) cols")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Task { await workspace.removeSource(source) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Remove \(source.displayName)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(selected ? Color.accentColor.opacity(0.11) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private var resultArea: some View {
        VStack(spacing: 0) {
            resultToolbar
            Divider().opacity(0.45)
            if workspace.result.columns.isEmpty {
                ContentUnavailableView(
                    "No result yet",
                    systemImage: "tablecells",
                    description: Text("Ask a data question or run the selected workflow.")
                )
            } else {
                DataResultTable(table: workspace.result)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultToolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.currentPlan?.title ?? workspace.selectedSource?.displayName ?? "Result")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(workspace.status)
                    .font(.system(size: 10))
                    .foregroundStyle(workspace.errorMessage == nil ? Color.secondary : Color.red)
                    .lineLimit(1)
            }
            Spacer()
            if workspace.isRunning {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                exportResult()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(!workspace.canExport)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    private var askPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Label("Ask Tidy", systemImage: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                Text(workspace.mode.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(14)

            Divider().opacity(0.45)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if workspace.messages.isEmpty {
                        Text("TRY ASKING")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                        ForEach(workspace.mode.examplePrompts, id: \.self) { prompt in
                            Button {
                                question = prompt
                            } label: {
                                Text(prompt)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(NSColor.labelColor))
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        ForEach(workspace.messages) { message in
                            DataMessageBubble(message: message)
                        }
                    }

                    if let error = workspace.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
            }

            Divider().opacity(0.45)
            VStack(spacing: 9) {
                TextEditor(text: $question)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 72, maxHeight: 110)
                    .padding(7)
                    .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(NSColor.separatorColor).opacity(0.7), lineWidth: 0.5)
                    }
                    .overlay(alignment: .topLeading) {
                        if question.isEmpty {
                            Text(workspace.mode.promptPlaceholder)
                                .font(.system(size: 12))
                                .foregroundStyle(Color(NSColor.placeholderTextColor))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 15)
                                .allowsHitTesting(false)
                        }
                    }

                HStack {
                    Text("Runs locally; AI plans and explains")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        let submitted = question
                        question = ""
                        Task { await workspace.run(question: submitted) }
                    } label: {
                        if workspace.isRunning {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(workspace.mode.title, systemImage: "arrow.up.circle.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!workspace.canRun || workspace.isRunning)
                }
            }
            .padding(12)
        }
        .frame(width: 310)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
    }

    private func chooseCSVs() {
        let panel = NSOpenPanel()
        panel.title = "Choose CSV Files"
        panel.prompt = "Add to Tidy Data"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        Task { await workspace.addCSVs(panel.urls) }
    }

    private func exportResult() {
        let panel = NSSavePanel()
        panel.title = "Export CSV Result"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "tidy-result.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await workspace.exportCurrentResult(to: url) }
    }
}

private struct DataResultTable: View {
    let table: DataTable
    private let columnWidth: CGFloat = 156
    private let rowHeight: CGFloat = 31

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    rowNumberCell("#", header: true)
                    ForEach(Array(table.columns.enumerated()), id: \.offset) { _, column in
                        tableCell(column, header: true)
                    }
                }

                ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 0) {
                        rowNumberCell("\(index + 1)", header: false)
                        ForEach(Array(table.columns.indices), id: \.self) { columnIndex in
                            tableCell(columnIndex < row.count ? row[columnIndex] ?? "NULL" : "", header: false)
                        }
                    }
                    .background(index.isMultiple(of: 2) ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.34))
                }
            }
        }
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

    private func tableCell(_ value: String, header: Bool) -> some View {
        Text(value)
            .font(.system(size: header ? 10 : 11, weight: header ? .semibold : .regular, design: header ? .rounded : .default))
            .foregroundStyle(header ? Color(NSColor.secondaryLabelColor) : Color(NSColor.labelColor))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: columnWidth, height: rowHeight, alignment: .leading)
            .padding(.horizontal, 8)
            .background(header ? Color(NSColor.controlBackgroundColor) : Color.clear)
            .overlay(alignment: .trailing) { Divider().opacity(0.35) }
            .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }

    private func rowNumberCell(_ value: String, header: Bool) -> some View {
        Text(value)
            .font(.system(size: 9, weight: header ? .semibold : .regular, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: 46, height: rowHeight, alignment: .trailing)
            .padding(.trailing, 8)
            .background(Color(NSColor.controlBackgroundColor))
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
            message.role == .user ? Color.accentColor.opacity(0.10) : Color(NSColor.controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 9)
        )
    }
}
