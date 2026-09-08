import Foundation

@MainActor
final class DataWorkspaceService: ObservableObject {
    @Published private(set) var mode: DataWorkspaceMode = .lookup
    @Published private(set) var sources: [DataSource] = []
    @Published private(set) var selectedSourceID: UUID?
    @Published private(set) var result: DataTable = .empty
    @Published private(set) var currentPlan: DataAIPlan?
    @Published private(set) var messages: [DataWorkspaceMessage] = []
    @Published private(set) var status = "Add CSV files or try the sample workspace."
    @Published private(set) var isRunning = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var resultCounts: [DataResultCount] = []
    @Published private(set) var recipes: [DataWorkflowRecipe] = []
    @Published var configuration = DataWorkflowConfiguration()

    private let engine: any TabularDataEngine
    private let ai: DataAIService
    private let defaults: UserDefaults
    private var currentSQL: String?
    private var completedConfiguration: DataWorkflowConfiguration?
    private var completedMode: DataWorkspaceMode?
    private var completedSourceIDs: [UUID] = []

    init(logStore: AIRequestLogStore, engine: any TabularDataEngine = DuckDBDataEngine(), defaults: UserDefaults = .standard) {
        self.engine = engine
        self.defaults = defaults
        ai = DataAIService(logStore: logStore)
        if let data = defaults.data(forKey: AppDefaults.dataWorkflowRecipes),
           let saved = try? JSONDecoder().decode([DataWorkflowRecipe].self, from: data) {
            recipes = saved
        }
    }

    var selectedSource: DataSource? { sources.first { $0.id == selectedSourceID } }
    var mainSource: DataSource? { sources.first { $0.id == configuration.leftID } }
    var referenceSource: DataSource? { sources.first { $0.id == configuration.rightID } }
    var configurationProblem: String? {
        do {
            _ = try DataWorkflowBuilder.build(mode: mode, configuration: configuration, sources: sources)
            return nil
        } catch { return error.localizedDescription }
    }
    var canRun: Bool { !isRunning && configurationProblem == nil }
    var resultIsOutdated: Bool {
        currentPlan != nil && (completedConfiguration != configuration || completedMode != mode || completedSourceIDs != sources.map(\.id))
    }
    var canExport: Bool { currentSQL != nil && !result.columns.isEmpty && !isRunning && !resultIsOutdated }

    func addCSVs(_ urls: [URL]) async {
        guard !isRunning else { return }
        let newURLs = Array(Set(urls)).sorted { $0.lastPathComponent < $1.lastPathComponent }.filter { url in
            url.pathExtension.lowercased() == "csv" && !sources.contains { $0.url == url }
        }
        guard !newURLs.isEmpty else { return }
        isRunning = true
        defer { isRunning = false }
        errorMessage = nil
        status = "Importing CSV files…"
        var failures: [String] = []
        for url in newURLs {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            let id = UUID()
            let tableName = "tidy_source_\(id.uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
            do {
                sources.append(try await engine.registerCSV(url, id: id, tableName: tableName))
            } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        refreshConfiguration()
        if selectedSourceID == nil, let first = sources.first {
            selectedSourceID = first.id
            await preview(first)
        }
        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
        status = failures.isEmpty ? "Loaded \(sources.count) tables. Choose a workflow to begin." : "Some files could not be imported."
    }

    func removeSource(_ source: DataSource) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            try await engine.removeTable(named: source.tableName)
            sources.removeAll { $0.id == source.id }
            refreshConfiguration()
            clearResult()
            selectedSourceID = sources.first?.id
            if let first = sources.first { await preview(first) }
        } catch { errorMessage = error.localizedDescription }
    }

    func selectSource(_ source: DataSource) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        selectedSourceID = source.id
        await preview(source)
    }

    func changeMode(_ newMode: DataWorkspaceMode) {
        guard !isRunning else { return }
        mode = newMode
        errorMessage = nil
        refreshConfiguration()
    }

    func selectMain(_ id: UUID?) {
        configuration.leftID = id
        if configuration.rightID == id { configuration.rightID = sources.first { $0.id != id }?.id }
        refreshConfiguration()
    }

    func selectReference(_ id: UUID?) {
        configuration.rightID = id
        refreshConfiguration()
    }

    func runWorkflow() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        errorMessage = nil
        do {
            let workflow = try DataWorkflowBuilder.build(mode: mode, configuration: configuration, sources: sources)
            status = "Checking matching keys and values…"
            for check in workflow.checks {
                let validation = try await engine.query(check.sql, limit: 1)
                if let row = validation.rows.first, let value = row.first, (Int(value ?? "0") ?? 0) > 0 {
                    throw DataWorkspaceError.invalidConfiguration(check.message)
                }
            }
            try await execute(workflow.plan)
        } catch { fail(error) }
    }

    func run(question: String) async {
        guard !isRunning, !sources.isEmpty, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isRunning = true
        defer { isRunning = false }
        errorMessage = nil
        status = "Planning your question…"
        messages.append(DataWorkspaceMessage(role: .user, text: question))
        do {
            let proposed = try await ai.plan(question: question, mode: mode, sources: sources, previousPlan: currentPlan)
            let sql = try DataQueryBuilder.validateReadOnlySQL(proposed.sql, allowedTables: Set(sources.map(\.tableName)))
            let plan = DataAIPlan(title: proposed.title, summary: proposed.summary, sql: sql, steps: proposed.steps)
            try await execute(plan)
            status = "Explaining results…"
            let explanation = (try? await ai.explain(question: question, plan: plan, result: result)) ?? plan.summary
            messages.append(DataWorkspaceMessage(role: .assistant, text: explanation))
            status = "\(result.totalRowCount.formatted()) result rows."
        } catch { fail(error) }
    }

    func exportCurrentResult(to url: URL) async {
        guard canExport, let currentSQL else { return }
        isRunning = true
        defer { isRunning = false }
        errorMessage = nil
        do {
            try await engine.exportCSV(query: currentSQL, to: url)
            status = "Exported all \(result.totalRowCount.formatted()) rows to \(url.lastPathComponent)."
        } catch { fail(error) }
    }

    func useResultAsSource() async {
        guard canExport, currentPlan != nil, let currentSQL else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            var used = Set<String>()
            let columns = result.columns.map { column -> String in
                var name = column.hasPrefix("_tidy_") ? "result_" + column.dropFirst(6) : column
                while used.contains(name.lowercased()) { name += "_2" }
                used.insert(name.lowercased())
                return "\(DataQueryBuilder.quotedIdentifier(column)) AS \(DataQueryBuilder.quotedIdentifier(name))"
            }
            let id = UUID()
            let source = try await engine.registerQuery(
                "SELECT \(columns.joined(separator: ", ")) FROM (\(currentSQL)) result",
                id: id,
                tableName: "tidy_result_" + id.uuidString.replacingOccurrences(of: "-", with: ""),
                displayName: "\(mode.title) result \(sources.count + 1)"
            )
            sources.append(source)
            configuration.leftID = source.id
            selectedSourceID = source.id
            refreshConfiguration()
            await preview(source)
            status = "Result added as a table. Continue with another workflow."
        } catch { fail(error) }
    }

    func saveRecipe(name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, configurationProblem == nil else { return }
        var settings = configuration
        settings.leftID = nil
        settings.rightID = nil
        recipes.append(DataWorkflowRecipe(id: UUID(), name: name, mode: mode, configuration: settings))
        persistRecipes()
    }

    func applyRecipe(_ recipe: DataWorkflowRecipe) {
        guard !isRunning else { return }
        let left = configuration.leftID
        let right = configuration.rightID
        mode = recipe.mode
        configuration = recipe.configuration
        configuration.leftID = left
        configuration.rightID = right
        errorMessage = nil
        status = "Loaded \(recipe.name). Check table roles and columns, then preview."
    }

    func deleteRecipe(_ recipe: DataWorkflowRecipe) {
        recipes.removeAll { $0.id == recipe.id }
        persistRecipes()
    }

    func loadSample() async {
        guard !isRunning else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TidyDataSample-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let files = [
                ("orders.csv", "order_id,customer_id,region,amount,status\n001,C01,North,120,paid\n002,C02,South,85,pending\n003,C01,North,60,paid\n004,C99,West,200,pending\n"),
                ("customers.csv", "customer_id,customer_name,region\nC01,Avery,North\nC02,Jordan,South\nC03,Sam,East\n"),
                ("orders-updated.csv", "order_id,customer_id,region,amount,status\n001,C01,North,120,paid\n002,C02,South,90,paid\n003,C01,North,60,paid\n005,C03,East,150,pending\n")
            ]
            for (name, contents) in files { try Data(contents.utf8).write(to: folder.appendingPathComponent(name)) }
            await addCSVs(files.map { folder.appendingPathComponent($0.0) })
            mode = .lookup
            configuration.leftID = sources.first { $0.url == folder.appendingPathComponent("orders.csv") }?.id
            configuration.rightID = sources.first { $0.url == folder.appendingPathComponent("customers.csv") }?.id
            refreshConfiguration()
            configuration.leftKey = "customer_id"
            configuration.rightKey = "customer_id"
            configuration.valueColumn = "customer_name"
            await runWorkflow()
        } catch { fail(error) }
    }

    private func execute(_ plan: DataAIPlan) async throws {
        status = "Calculating across all rows…"
        let table = try await engine.query(plan.sql, limit: 250)
        var counts: [DataResultCount] = []
        if table.columns.contains("_tidy_status") {
            let grouped = try await engine.query("SELECT \"_tidy_status\", COUNT(*) FROM (\(plan.sql)) result GROUP BY \"_tidy_status\" ORDER BY \"_tidy_status\"", limit: 20)
            counts = grouped.rows.compactMap { row in
                guard row.count >= 2, let label = row[0], let number = row[1], let count = Int(number) else { return nil }
                return DataResultCount(label: label, count: count)
            }
        }
        result = table
        resultCounts = counts
        currentPlan = plan
        currentSQL = plan.sql
        completedConfiguration = configuration
        completedMode = mode
        completedSourceIDs = sources.map(\.id)
        status = "\(table.totalRowCount.formatted()) result rows · original files unchanged"
    }

    private func preview(_ source: DataSource) async {
        errorMessage = nil
        do {
            let sql = DataQueryBuilder.preview(tableName: source.tableName)
            let table = try await engine.query(sql, limit: 250)
            clearResult()
            result = table
            currentSQL = sql
            status = "Source preview · \(source.rowCount.formatted()) rows · \(source.columns.count) columns"
        } catch { fail(error) }
    }

    private func clearResult() {
        result = .empty
        resultCounts = []
        currentPlan = nil
        currentSQL = nil
        completedConfiguration = nil
        messages = []
    }

    private func fail(_ error: Error) {
        clearResult()
        errorMessage = error.localizedDescription
        status = "Review the settings and try again."
    }

    private func refreshConfiguration() {
        if mainSource == nil { configuration.leftID = sources.first?.id }
        if referenceSource == nil || configuration.leftID == configuration.rightID {
            configuration.rightID = sources.first { $0.id != configuration.leftID }?.id
        }
        if let mainSource, !mainSource.columns.contains(where: { $0.name == configuration.leftKey }) {
            configuration.leftKey = DataQueryBuilder.suggestedComparisonKey(for: [mainSource]) ?? ""
        }
        if let referenceSource, !referenceSource.columns.contains(where: { $0.name == configuration.rightKey }) {
            configuration.rightKey = referenceSource.columns.first { $0.name.caseInsensitiveCompare(configuration.leftKey) == .orderedSame }?.name
                ?? DataQueryBuilder.suggestedComparisonKey(for: [referenceSource]) ?? ""
        }
        let valueSource = mode == .lookup ? referenceSource : mainSource
        if let valueSource, !valueSource.columns.contains(where: { $0.name == configuration.valueColumn }) {
            configuration.valueColumn = valueSource.columns.first?.name ?? ""
        }
        if let mainSource {
            if !mainSource.columns.contains(where: { $0.name == configuration.groupColumn }) { configuration.groupColumn = "" }
            if !mainSource.columns.contains(where: { $0.name == configuration.metricColumn }) { configuration.metricColumn = mainSource.columns.first?.name ?? "" }
        }
    }

    private func persistRecipes() {
        if let data = try? JSONEncoder().encode(recipes) { defaults.set(data, forKey: AppDefaults.dataWorkflowRecipes) }
    }
}
