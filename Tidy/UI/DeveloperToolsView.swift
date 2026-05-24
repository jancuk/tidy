import AppKit
import SwiftUI

enum DeveloperTool: String, CaseIterable, Identifiable {
    case json
    case jwt
    case diff
    case unixTime
    case csv
    case cron

    var id: String { rawValue }

    var title: String {
        switch self {
        case .json: "JSON Format / Validate"
        case .jwt: "JWT Debugger"
        case .diff: "Text Diff Checker"
        case .unixTime: "Unix Time Converter"
        case .csv: "CSV / JSON Converter"
        case .cron: "Cron Job Parser"
        }
    }

    var subtitle: String {
        switch self {
        case .json: "Pretty print and validate JSON"
        case .jwt: "Decode header, payload, and claims"
        case .diff: "Compare text line by line"
        case .unixTime: "Convert epoch seconds or milliseconds"
        case .csv: "Convert CSV to JSON and JSON to CSV"
        case .cron: "Explain schedules and next runs"
        }
    }

    var systemImage: String {
        switch self {
        case .json: "curlybraces"
        case .jwt: "key.horizontal"
        case .diff: "arrow.left.arrow.right"
        case .unixTime: "clock"
        case .csv: "tablecells"
        case .cron: "calendar.badge.clock"
        }
    }
}

struct DeveloperToolsView: View {
    @State private var selection: DeveloperTool = .json
    @State private var query = ""

    private var tools: [DeveloperTool] {
        let all = DeveloperTool.allCases
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            toolsSidebar

            Group {
                switch selection {
                case .json:
                    JSONFormatterView()
                case .jwt:
                    JWTDebuggerView()
                case .diff:
                    TextDiffCheckerView()
                case .unixTime:
                    UnixTimeConverterView()
                case .csv:
                    CSVJSONConverterView()
                case .cron:
                    CronParserView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .navigationTitle("Developer Tools")
    }

    private var toolsSidebar: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                TextField("Search tools", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(0.8), lineWidth: 0.5)
            )
            .padding(10)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(tools) { tool in
                        ToolSidebarRow(tool: tool, selected: selection == tool) {
                            selection = tool
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .frame(width: 200)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .trailing) { Divider() }
    }
}

private struct ToolSidebarRow: View {
    let tool: DeveloperTool
    let selected: Bool
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 13))
                    .frame(width: 16)
                    .foregroundStyle(selected ? selectedForeground : Color(NSColor.secondaryLabelColor))
                VStack(alignment: .leading, spacing: 1) {
                    Text(tool.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? selectedForeground : Color(NSColor.labelColor))
                    Text(tool.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(selected ? selectedForeground.opacity(0.7) : Color(NSColor.secondaryLabelColor))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected
                        ? selectedBackground
                        : (isHovered ? Color(NSColor.labelColor).opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var selectedBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.15)
            : Color(red: 0.23, green: 0.23, blue: 0.24).opacity(0.9)
    }

    private var selectedForeground: Color {
        colorScheme == .dark ? Color(NSColor.labelColor) : .white
    }
}

private struct JSONFormatterView: View {
    @State private var input = "{\n  \"name\": \"Tidy\",\n  \"features\": [\"grammar\", \"clipboard\", \"developer tools\"]\n}"
    @State private var minified = false
    @State private var result = JSONTool.format("{\n  \"name\": \"Tidy\",\n  \"features\": [\"grammar\", \"clipboard\", \"developer tools\"]\n}")

    var body: some View {
        ToolScreen(
            title: DeveloperTool.json.title,
            subtitle: "Format, minify, and validate JSON without leaving Tidy.",
            status: result.status,
            isError: result.isError
        ) {
            Toggle("Minify", isOn: $minified)
                .toggleStyle(.switch)
                .onChange(of: minified) { _, _ in run() }
            Button("Validate") { run() }
            Button("Copy Output") { Pasteboard.copy(result.output) }
        } content: {
            HStack(spacing: 12) {
                CodeEditorPanel(title: "JSON Input", text: $input, placeholder: "Paste JSON here") {
                    Button("Sample") { sample() }
                    Button("Clear") { input = ""; run() }
                }
                OutputPanel(title: "Output", text: result.output, isError: result.isError)
            }
        }
        .onChange(of: input) { _, _ in run() }
    }

    private func run() {
        result = JSONTool.format(input, minified: minified)
    }

    private func sample() {
        input = "{\"project\":\"Tidy\",\"count\":3,\"active\":true,\"tools\":[\"json\",\"jwt\",\"cron\"]}"
        run()
    }
}

private struct JWTDebuggerView: View {
    @State private var token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkF6aGFyIEFtaXIiLCJpYXQiOjE3MTYyMzkwMjIsImV4cCI6MTc0Nzc3NTAyMn0.signature"
    @State private var result = JWTTool.decode("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkF6aGFyIEFtaXIiLCJpYXQiOjE3MTYyMzkwMjIsImV4cCI6MTc0Nzc3NTAyMn0.signature")

    var body: some View {
        ToolScreen(
            title: DeveloperTool.jwt.title,
            subtitle: "Decode JWT header, payload, and date claims. Signature verification is intentionally not performed.",
            status: result.status,
            isError: result.isError
        ) {
            Button("Decode") { decode() }
            Button("Copy Payload") { Pasteboard.copy(result.payloadJSON) }
            Button("Clear") { token = ""; decode() }
        } content: {
            VStack(spacing: 12) {
                CodeEditorPanel(title: "JWT Token", text: $token, minHeight: 86, placeholder: "Paste a JWT token")
                HStack(spacing: 12) {
                    OutputPanel(title: "Header", text: result.headerJSON, isError: result.isError)
                    OutputPanel(title: "Payload", text: result.payloadJSON, isError: result.isError)
                }
                ClaimsPanel(claims: result.claims, signature: result.signature)
            }
        }
        .onChange(of: token) { _, _ in decode() }
    }

    private func decode() {
        result = JWTTool.decode(token)
    }
}

private struct TextDiffCheckerView: View {
    @State private var oldText = "Tidy fixes grammar.\nClipboard history stays available.\nDeveloper tools are coming."
    @State private var newText = "Tidy fixes grammar quickly.\nClipboard history stays available.\nDeveloper tools are ready."

    private var rows: [DiffRow] {
        TextDiffTool.lineDiff(old: oldText, new: newText)
    }

    private var changeCount: Int {
        rows.filter { $0.kind != .unchanged }.count
    }

    var body: some View {
        ToolScreen(
            title: DeveloperTool.diff.title,
            subtitle: "Compare two text blocks and inspect added or removed lines.",
            status: "\(changeCount) changed lines",
            isError: false
        ) {
            Button("Copy Diff") { Pasteboard.copy(diffOutput) }
            Button("Clear") { oldText = ""; newText = "" }
        } content: {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    CodeEditorPanel(title: "Original", text: $oldText, placeholder: "Original text")
                    CodeEditorPanel(title: "Changed", text: $newText, placeholder: "Changed text")
                }
                DiffOutputPanel(rows: rows)
            }
        }
    }

    private var diffOutput: String {
        rows.map { row in
            switch row.kind {
            case .unchanged: "  \(row.text)"
            case .added: "+ \(row.text)"
            case .removed: "- \(row.text)"
            }
        }.joined(separator: "\n")
    }
}

private struct UnixTimeConverterView: View {
    @State private var timestamp = String(Int(Date().timeIntervalSince1970))
    @State private var result = UnixTimeTool.convert(String(Int(Date().timeIntervalSince1970)))

    var body: some View {
        ToolScreen(
            title: DeveloperTool.unixTime.title,
            subtitle: "Convert Unix timestamps in seconds or milliseconds to readable dates.",
            status: status,
            isError: isError
        ) {
            Button("Use Current Time") {
                timestamp = String(Int(Date().timeIntervalSince1970))
                convert()
            }
            Button("Copy ISO") {
                if case .success(let value) = result {
                    Pasteboard.copy(value.iso8601)
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                LabeledTextField(title: "Unix Timestamp", text: $timestamp, prompt: "Seconds or milliseconds")
                    .frame(maxWidth: 460)
                UnixResultPanel(result: result)
                Spacer()
            }
        }
        .onChange(of: timestamp) { _, _ in convert() }
    }

    private var status: String {
        switch result {
        case .success: "Converted timestamp."
        case .failure(let message): message
        }
    }

    private var isError: Bool {
        if case .failure = result { return true }
        return false
    }

    private func convert() {
        result = UnixTimeTool.convert(timestamp)
    }
}

private enum CSVMode: String, CaseIterable, Identifiable {
    case csvToJSON = "CSV to JSON"
    case jsonToCSV = "JSON to CSV"
    var id: String { rawValue }
}

private struct CSVJSONConverterView: View {
    @State private var mode: CSVMode = .csvToJSON
    @State private var input = "name,role\nTidy,Grammar assistant\nDevTools,Utilities"
    @State private var result = CSVTool.csvToJSON("name,role\nTidy,Grammar assistant\nDevTools,Utilities")

    var body: some View {
        ToolScreen(
            title: DeveloperTool.csv.title,
            subtitle: "Convert tabular CSV data into JSON records or flatten JSON objects back to CSV.",
            status: result.status,
            isError: result.isError
        ) {
            Picker("Mode", selection: $mode) {
                ForEach(CSVMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .onChange(of: mode) { _, _ in sample() }
            Button("Convert") { convert() }
            Button("Copy Output") { Pasteboard.copy(result.output) }
        } content: {
            HStack(spacing: 12) {
                CodeEditorPanel(title: mode.rawValue == CSVMode.csvToJSON.rawValue ? "CSV Input" : "JSON Input", text: $input) {
                    Button("Sample") { sample() }
                    Button("Clear") { input = ""; convert() }
                }
                OutputPanel(title: "Output", text: result.output, isError: result.isError)
            }
        }
        .onChange(of: input) { _, _ in convert() }
    }

    private func convert() {
        switch mode {
        case .csvToJSON:
            result = CSVTool.csvToJSON(input)
        case .jsonToCSV:
            result = CSVTool.jsonToCSV(input)
        }
    }

    private func sample() {
        switch mode {
        case .csvToJSON:
            input = "name,role\nTidy,Grammar assistant\nDevTools,Utilities"
        case .jsonToCSV:
            input = "[\n  {\"name\":\"Tidy\",\"role\":\"Grammar assistant\"},\n  {\"name\":\"DevTools\",\"role\":\"Utilities\"}\n]"
        }
        convert()
    }
}

private struct CronParserView: View {
    @State private var expression = "*/15 9-17 * * mon-fri"
    @State private var result = CronTool.parse("*/15 9-17 * * mon-fri")

    var body: some View {
        ToolScreen(
            title: DeveloperTool.cron.title,
            subtitle: "Parse standard five-field cron expressions and preview upcoming run times.",
            status: result.status,
            isError: result.isError
        ) {
            Button("Parse") { parse() }
            Button("Every Hour") { expression = "0 * * * *"; parse() }
            Button("Weekday Workday") { expression = "*/15 9-17 * * mon-fri"; parse() }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                LabeledTextField(title: "Cron Expression", text: $expression, prompt: "*/15 9-17 * * mon-fri")
                    .frame(maxWidth: 520)
                CronResultPanel(result: result)
                Spacer()
            }
        }
        .onChange(of: expression) { _, _ in parse() }
    }

    private func parse() {
        result = CronTool.parse(expression)
    }
}

private struct ToolScreen<ToolbarContent: View, Content: View>: View {
    let title: String
    let subtitle: String
    let status: String
    let isError: Bool
    @ViewBuilder let toolbar: ToolbarContent
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(NSColor.labelColor))
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    }
                    Spacer()
                    HStack(spacing: 6) { toolbar }
                        .controlSize(.small)
                }
                StatusPill(text: status, isError: isError)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(alignment: .bottom) { Divider() }

            content.padding(14)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct StatusPill: View {
    let text: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isError ? Color.red : Color.green)
                .frame(width: 6, height: 6)
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(isError ? Color.red : Color.green)
    }
}

private struct CodeEditorPanel<Actions: View>: View {
    let title: String
    @Binding var text: String
    var minHeight: CGFloat = 260
    var placeholder = ""
    @ViewBuilder var actions: Actions

    init(title: String, text: Binding<String>, minHeight: CGFloat = 260, placeholder: String = "", @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.title = title
        self._text = text
        self.minHeight = minHeight
        self.placeholder = placeholder
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: title) {
                actions
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: minHeight)

                if text.isEmpty && !placeholder.isEmpty {
                    Text(placeholder)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .panelStyle()
    }
}

private struct OutputPanel: View {
    let title: String
    let text: String
    let isError: Bool

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: title) {
                Button("Copy") { Pasteboard.copy(text) }
            }
            ScrollView {
                Text(text.isEmpty ? "Output will appear here." : text)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(isError ? .red : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .panelStyle()
    }
}

private struct DiffOutputPanel: View {
    let rows: [DiffRow]

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Line Diff") {
                Text("\(rows.count) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        HStack(alignment: .top, spacing: 10) {
                            Text(prefix(for: row.kind))
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                .frame(width: 18)
                            Text(row.text.isEmpty ? " " : row.text)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(background(for: row.kind))
                    }
                }
                .padding(.vertical, 6)
            }
            .background(Color(NSColor.textBackgroundColor))
            .frame(minHeight: 220)
        }
        .panelStyle()
    }

    private func prefix(for kind: DiffKind) -> String {
        switch kind {
        case .unchanged: " "
        case .added: "+"
        case .removed: "-"
        }
    }

    private func background(for kind: DiffKind) -> Color {
        switch kind {
        case .unchanged: Color.clear
        case .added: Color.green.opacity(0.14)
        case .removed: Color.red.opacity(0.14)
        }
    }
}

private struct ClaimsPanel: View {
    let claims: [(String, String)]
    let signature: String

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Claims & Signature") {
                Button("Copy Signature") { Pasteboard.copy(signature) }
            }
            VStack(alignment: .leading, spacing: 0) {
                if claims.isEmpty {
                    Text("Claims will appear here.")
                        .foregroundStyle(.secondary)
                        .padding(12)
                } else {
                    ForEach(claims, id: \.0) { key, value in
                        HStack(alignment: .top) {
                            Text(key)
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                .frame(width: 110, alignment: .leading)
                            Text(value)
                                .textSelection(.enabled)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        Divider()
                    }
                }
                Text("Signature: \(signature)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .panelStyle()
    }
}

private struct UnixResultPanel: View {
    let result: UnixTimeConversionResult

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Converted Date")
            VStack(alignment: .leading, spacing: 12) {
                switch result {
                case .success(let value):
                    InfoRow(label: "Local", value: value.local)
                    InfoRow(label: "UTC", value: value.utc)
                    InfoRow(label: "ISO 8601", value: value.iso8601)
                    InfoRow(label: "Seconds", value: String(value.seconds))
                    InfoRow(label: "Milliseconds", value: String(value.milliseconds))
                case .failure(let message):
                    Text(message)
                        .foregroundStyle(.red)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.textBackgroundColor))
        }
        .panelStyle()
    }
}

private struct CronResultPanel: View {
    let result: CronParseResult

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Schedule")
            VStack(alignment: .leading, spacing: 14) {
                if result.isError {
                    Text(result.status)
                        .foregroundStyle(.red)
                } else {
                    InfoRow(label: "Description", value: result.description)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Fields")
                            .font(.headline)
                        ForEach(result.fields, id: \.0) { label, value in
                            InfoRow(label: label, value: value)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Next Runs")
                            .font(.headline)
                        if result.nextRuns.isEmpty {
                            Text("No runs found in the next year.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(result.nextRuns, id: \.self) { run in
                                Text(run)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.textBackgroundColor))
        }
        .panelStyle()
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

private struct LabeledTextField: View {
    let title: String
    @Binding var text: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct PanelHeader<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(title: String, @ViewBuilder content: () -> Content = { EmptyView() }) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
            Spacer()
            HStack(spacing: 8) { content }
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }
}

private struct PanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.separator, lineWidth: 0.5))
    }
}

private extension View {
    func panelStyle() -> some View {
        modifier(PanelModifier())
    }
}

private enum Pasteboard {
    static func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
