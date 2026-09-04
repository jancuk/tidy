import Foundation

@MainActor
final class DataWorkspaceService: ObservableObject {
    @Published var mode: DataWorkspaceMode = .analyze
    @Published private(set) var sources: [DataSource] = []
    @Published private(set) var selectedSourceID: UUID?
    @Published private(set) var result: DataTable = .empty
    @Published private(set) var currentPlan: DataAIPlan?
    @Published private(set) var insight = ""
    @Published private(set) var messages: [DataWorkspaceMessage] = []
    @Published private(set) var status = "Add a CSV file to begin."
    @Published private(set) var isRunning = false
    @Published private(set) var errorMessage: String?
    @Published var comparisonKey = ""

    private let engine: any TabularDataEngine
    private let ai: DataAIService
    private var currentSQL: String?
    private var securityScopedURLs: Set<URL> = []

    init(
        logStore: AIRequestLogStore,
        engine: any TabularDataEngine = DuckDBDataEngine()
    ) {
        self.engine = engine
        ai = DataAIService(logStore: logStore)
    }

    var selectedSource: DataSource? {
        sources.first { $0.id == selectedSourceID }
    }

    var comparisonColumns: [String] {
        guard sources.count >= 2 else { return [] }
        let rightNames = Set(sources[1].columns.map { $0.name.lowercased() })
        return sources[0].columns.map(\.name).filter { rightNames.contains($0.lowercased()) }
    }

    var canRun: Bool {
        switch mode {
        case .analyze: !sources.isEmpty
        case .combine: sources.count >= 2
        case .compare: sources.count >= 2 && !comparisonKey.isEmpty
        }
    }

    var canExport: Bool {
        currentSQL != nil && !result.columns.isEmpty && !isRunning
    }

    func addCSVs(_ urls: [URL]) async {
        let newURLs = urls.filter { url in
            url.pathExtension.lowercased() == "csv" && !sources.contains { $0.url == url }
        }
        guard !newURLs.isEmpty else { return }

        isRunning = true
        errorMessage = nil
        status = "Importing CSV files…"
        var failures: [String] = []

        for url in newURLs {
            let didAccess = url.startAccessingSecurityScopedResource()
            if didAccess { securityScopedURLs.insert(url) }
            let id = UUID()
            let tableName = "tidy_source_\(id.uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
            do {
                let source = try await engine.registerCSV(url, id: id, tableName: tableName)
                sources.append(source)
            } catch {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                    securityScopedURLs.remove(url)
                }
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        refreshComparisonKey()
        if selectedSourceID == nil, let first = sources.first {
            selectedSourceID = first.id
            await preview(first)
        }
        isRunning = false
        if failures.isEmpty {
            status = "Loaded \(sources.count) CSV \(sources.count == 1 ? "file" : "files")."
        } else {
            errorMessage = failures.joined(separator: "\n")
            status = sources.isEmpty ? "No CSV files were imported." : "Some CSV files could not be imported."
        }
    }

    func removeSource(_ source: DataSource) async {
        do {
            try await engine.removeTable(named: source.tableName)
        } catch {
            errorMessage = error.localizedDescription
        }
        sources.removeAll { $0.id == source.id }
        if securityScopedURLs.remove(source.url) != nil {
            source.url.stopAccessingSecurityScopedResource()
        }
        refreshComparisonKey()
        currentPlan = nil
        insight = ""
        messages = []
        currentSQL = nil

        if selectedSourceID == source.id {
            selectedSourceID = sources.first?.id
            if let first = sources.first {
                await preview(first)
            } else {
                result = .empty
                status = "Add a CSV file to begin."
            }
        }
    }

    func selectSource(_ source: DataSource) async {
        selectedSourceID = source.id
        await preview(source)
    }

    func changeMode(_ newMode: DataWorkspaceMode) {
        mode = newMode
        errorMessage = nil
        if newMode == .compare { refreshComparisonKey() }
    }

    func run(question rawQuestion: String) async {
        let question = resolvedQuestion(rawQuestion)
        do {
            try validateInputs()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        isRunning = true
        errorMessage = nil
        status = mode == .analyze ? "Planning analysis…" : "Planning \(mode.rawValue)…"
        messages.append(DataWorkspaceMessage(role: .user, text: question))

        do {
            let plan = try await makePlan(question: question, rawQuestion: rawQuestion)
            let validatedSQL = try DataQueryBuilder.validateReadOnlySQL(
                plan.sql,
                allowedTables: Set(sources.map(\.tableName))
            )
            currentPlan = DataAIPlan(
                title: plan.title,
                summary: plan.summary,
                sql: validatedSQL,
                steps: plan.steps
            )
            status = "Running locally with DuckDB…"
            result = try await engine.query(validatedSQL, limit: 250)
            currentSQL = validatedSQL
            status = "\(result.totalRowCount.formatted()) result \(result.totalRowCount == 1 ? "row" : "rows")."

            if rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && mode != .analyze {
                insight = plan.summary
            } else {
                status = "Explaining verified results…"
                do {
                    insight = try await ai.explain(question: question, plan: plan, result: result)
                } catch {
                    insight = plan.summary
                }
                status = "\(result.totalRowCount.formatted()) result \(result.totalRowCount == 1 ? "row" : "rows")."
            }
            messages.append(DataWorkspaceMessage(role: .assistant, text: insight))
        } catch {
            errorMessage = error.localizedDescription
            status = "The request could not be completed."
            messages.append(DataWorkspaceMessage(role: .assistant, text: error.localizedDescription))
        }
        isRunning = false
    }

    func exportCurrentResult(to url: URL) async {
        guard let currentSQL else { return }
        isRunning = true
        errorMessage = nil
        status = "Exporting CSV…"
        do {
            try await engine.exportCSV(query: currentSQL, to: url)
            status = "Exported \(url.lastPathComponent)."
        } catch {
            errorMessage = error.localizedDescription
            status = "Export failed."
        }
        isRunning = false
    }

    private func preview(_ source: DataSource) async {
        isRunning = true
        errorMessage = nil
        status = "Loading preview…"
        let sql = DataQueryBuilder.preview(tableName: source.tableName)
        do {
            result = try await engine.query(sql, limit: 250)
            currentSQL = sql
            currentPlan = nil
            insight = ""
            status = "\(source.rowCount.formatted()) rows · \(source.columns.count) columns"
        } catch {
            errorMessage = error.localizedDescription
            status = "Preview failed."
        }
        isRunning = false
    }

    private func makePlan(question: String, rawQuestion: String) async throws -> DataAIPlan {
        let hasCustomQuestion = !rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if mode == .combine && !hasCustomQuestion {
            return DataAIPlan(
                title: "Combined CSV files",
                summary: "Appended all imported files by matching column names and added the source filename.",
                sql: try DataQueryBuilder.combine(sources),
                steps: ["Align matching columns", "Append all rows", "Add _tidy_source"]
            )
        }
        if mode == .compare && !hasCustomQuestion {
            guard sources.count >= 2 else { throw DataWorkspaceError.needsMultipleSources(.compare) }
            let sql = try DataQueryBuilder.compare(
                left: sources[0],
                right: sources[1],
                key: comparisonKey
            )
            return DataAIPlan(
                title: "CSV comparison",
                summary: "Compared the first two CSV files by \(comparisonKey) and classified every row.",
                sql: sql,
                steps: ["Match rows by \(comparisonKey)", "Compare shared fields", "Classify row status"]
            )
        }
        return try await ai.plan(
            question: question,
            mode: mode,
            sources: sources,
            previousPlan: currentPlan
        )
    }

    private func validateInputs() throws {
        guard !sources.isEmpty else { throw DataWorkspaceError.noSources }
        if mode == .combine && sources.count < 2 {
            throw DataWorkspaceError.needsMultipleSources(.combine)
        }
        if mode == .compare {
            guard sources.count >= 2 else { throw DataWorkspaceError.needsMultipleSources(.compare) }
            guard !comparisonColumns.isEmpty else { throw DataWorkspaceError.noSharedColumns }
            guard !comparisonKey.isEmpty else { throw DataWorkspaceError.noComparisonKey }
        }
    }

    private func resolvedQuestion(_ rawQuestion: String) -> String {
        let trimmed = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return switch mode {
        case .analyze: "Summarize the most useful patterns, totals, and data-quality issues in this data."
        case .combine: "Append all imported CSV files by matching column names."
        case .compare: "Show added, removed, changed, and unchanged rows."
        }
    }

    private func refreshComparisonKey() {
        let available = comparisonColumns
        if !available.contains(comparisonKey) {
            comparisonKey = DataQueryBuilder.suggestedComparisonKey(for: Array(sources.prefix(2))) ?? ""
        }
    }
}
