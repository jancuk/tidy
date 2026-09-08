import Foundation
import Testing
@testable import Tidy

struct DataWorkspaceTests {
    private func fixtures() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("id,customer,amount,status\n001,A,10,paid\n002,B,20,pending\n003,Z,30,paid\n".utf8)
            .write(to: folder.appendingPathComponent("orders.csv"))
        try Data("key,name\nA,Avery\nB,Jordan\n".utf8).write(to: folder.appendingPathComponent("customers.csv"))
        return folder
    }

    private func importSource(_ name: String, folder: URL, engine: DuckDBDataEngine) async throws -> DataSource {
        try await engine.registerCSV(folder.appendingPathComponent(name + ".csv"), id: UUID(), tableName: name)
    }

    @Test func lookupPreservesIdentifiersAndFlagsUnmatchedRows() async throws {
        let folder = try fixtures()
        defer { try? FileManager.default.removeItem(at: folder) }
        let engine = DuckDBDataEngine()
        let orders = try await importSource("orders", folder: folder, engine: engine)
        let customers = try await importSource("customers", folder: folder, engine: engine)
        var c = DataWorkflowConfiguration()
        c.leftID = orders.id; c.rightID = customers.id
        c.leftKey = "customer"; c.rightKey = "key"; c.valueColumn = "name"
        let workflow = try DataWorkflowBuilder.build(mode: .lookup, configuration: c, sources: [orders, customers])
        let result = try await engine.query(workflow.plan.sql + " ORDER BY l.id", limit: 10)
        #expect(result.totalRowCount == 3)
        #expect(result.rows[0] == ["001", "A", "10", "paid", "Avery", "Matched"])
        #expect(result.rows[2] == ["003", "Z", "30", "paid", nil, "Unmatched"])
        try Data("id,customer,amount,status\n999,A,900,changed\n".utf8).write(to: orders.url)
        let snapshot = try await engine.query(DataQueryBuilder.preview(tableName: orders.tableName), limit: 10)
        #expect(snapshot.totalRowCount == 3)
        #expect(snapshot.rows[0][0] == "001")
    }

    @Test func replacementSupportsLiteralQuotesAndDoesNotModifySource() async throws {
        let folder = try fixtures()
        defer { try? FileManager.default.removeItem(at: folder) }
        let engine = DuckDBDataEngine()
        let orders = try await importSource("orders", folder: folder, engine: engine)
        var c = DataWorkflowConfiguration()
        c.leftID = orders.id; c.valueColumn = "status"; c.find = "paid"; c.replacement = "customer's payment"
        let plan = try DataWorkflowBuilder.build(mode: .replace, configuration: c, sources: [orders])
        let result = try await engine.query(plan.plan.sql + " ORDER BY id", limit: 10)
        #expect(result.rows[0][3] == "customer's payment")
        #expect(result.rows[0].suffix(2) == ["paid", "Replaced"])
        #expect(result.rows[1].last == "Unchanged")
        let original = try await engine.query("SELECT status FROM orders ORDER BY id", limit: 10)
        #expect(original.rows[0] == ["paid"])
        c.exactReplacement = false; c.find = "aid"; c.replacement = ""
        let partial = try DataWorkflowBuilder.build(mode: .replace, configuration: c, sources: [orders])
        let partialResult = try await engine.query(partial.plan.sql + " ORDER BY id", limit: 10)
        #expect(partialResult.rows[0][3] == "p")
    }

    @Test func reconcileUsesSelectedKeysAndShowsEachChangeType() async throws {
        let folder = try fixtures()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("record_id,customer,amount,status\n001,A,10,paid\n002,B,25,paid\n004,C,40,pending\n".utf8)
            .write(to: folder.appendingPathComponent("after.csv"))
        let engine = DuckDBDataEngine()
        let before = try await importSource("orders", folder: folder, engine: engine)
        let after = try await importSource("after", folder: folder, engine: engine)
        var c = DataWorkflowConfiguration()
        c.leftID = before.id; c.rightID = after.id; c.leftKey = "id"; c.rightKey = "record_id"
        let plan = try DataWorkflowBuilder.build(mode: .compare, configuration: c, sources: [before, after])
        let result = try await engine.query(plan.plan.sql, limit: 10)
        #expect(result.totalRowCount == 3)
        #expect(Set(result.rows.compactMap { $0[1] }) == ["Added", "Removed", "Changed"])
        c.differencesOnly = false
        let all = try DataWorkflowBuilder.build(mode: .compare, configuration: c, sources: [before, after])
        let allResult = try await engine.query(all.plan.sql, limit: 10)
        #expect(allResult.totalRowCount == 4)
    }

    @Test func joinHonorsRowPolicyAndKeepsRepeatedMatches() async throws {
        let folder = try fixtures()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("key,name\nA,Avery\nA,Another\nB,Jordan\nC,Sam\n".utf8)
            .write(to: folder.appendingPathComponent("customers.csv"))
        let engine = DuckDBDataEngine()
        let orders = try await importSource("orders", folder: folder, engine: engine)
        let customers = try await importSource("customers", folder: folder, engine: engine)
        var c = DataWorkflowConfiguration()
        c.leftID = orders.id; c.rightID = customers.id; c.leftKey = "customer"; c.rightKey = "key"
        for (kind, expected) in [(DataJoinKind.left, 4), (.inner, 3), (.full, 5)] {
            c.joinKind = kind
            let workflow = try DataWorkflowBuilder.build(mode: .join, configuration: c, sources: [orders, customers])
            let result = try await engine.query(workflow.plan.sql, limit: 10)
            #expect(result.totalRowCount == expected)
            #expect(result.columns.contains("reference_name"))
        }
    }

    @Test func localAnalysisCalculatesAllRowsAndRejectsBadNumbers() async throws {
        let folder = try fixtures()
        defer { try? FileManager.default.removeItem(at: folder) }
        let engine = DuckDBDataEngine()
        let orders = try await importSource("orders", folder: folder, engine: engine)
        var c = DataWorkflowConfiguration()
        c.leftID = orders.id; c.aggregation = .sum; c.metricColumn = "amount"; c.groupColumn = "status"
        let workflow = try DataWorkflowBuilder.build(mode: .analyze, configuration: c, sources: [orders])
        let result = try await engine.query(workflow.plan.sql, limit: 1)
        #expect(result.totalRowCount == 2)
        #expect(result.isTruncated)
        #expect(result.rows[0] == ["paid", "40.0", "2"])
        c.metricColumn = "status"
        let bad = try DataWorkflowBuilder.build(mode: .analyze, configuration: c, sources: [orders])
        let check = try await engine.query(bad.checks[0].sql, limit: 1)
        #expect(check.rows == [["3"]])
        c.aggregation = .profile
        let profile = try DataWorkflowBuilder.build(mode: .analyze, configuration: c, sources: [orders])
        let quality = try await engine.query(profile.plan.sql, limit: 10)
        #expect(quality.totalRowCount == 4)
        #expect(quality.rows.first == ["id", "3", "0", "3"])
    }

    @Test @MainActor func workflowServiceBlocksAmbiguousKeysAndInvalidatesOldExports() async throws {
        let folder = try fixtures()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("key,name\nA,One\nA,Two\n,Missing\n".utf8).write(to: folder.appendingPathComponent("customers.csv"))
        let suite = "TidyDataTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = DataWorkspaceService(logStore: AIRequestLogStore(), defaults: defaults)
        await service.addCSVs([folder.appendingPathComponent("orders.csv"), folder.appendingPathComponent("customers.csv")])
        let orders = try #require(service.sources.first { $0.displayName == "orders.csv" })
        let customers = try #require(service.sources.first { $0.displayName == "customers.csv" })
        service.selectMain(orders.id); service.selectReference(customers.id)
        service.configuration.leftKey = "customer"; service.configuration.rightKey = "key"; service.configuration.valueColumn = "name"
        await service.runWorkflow()
        #expect(service.errorMessage?.contains("duplicate or missing") == true)
        #expect(!service.canExport)
        service.changeMode(.replace)
        service.configuration.valueColumn = "status"; service.configuration.find = "paid"; service.configuration.replacement = "done"
        await service.runWorkflow()
        #expect(service.canExport)
        #expect(service.resultCounts.first { $0.label == "Replaced" }?.count == 2)
        service.configuration.replacement = "settled"
        #expect(service.resultIsOutdated)
        #expect(!service.canExport)
        await service.runWorkflow()
        service.saveRecipe(name: "Settle payments")
        let restored = DataWorkspaceService(logStore: AIRequestLogStore(), defaults: defaults)
        #expect(restored.recipes.count == 1)
        #expect(restored.recipes[0].configuration.leftID == nil)
        #expect(restored.recipes[0].configuration.replacement == "settled")
        await service.useResultAsSource()
        #expect(service.sources.count == 3)
        #expect(service.mainSource?.columns.contains { $0.name == "result_status" } == true)
        service.changeMode(.analyze)
        await service.runWorkflow()
        #expect(service.errorMessage == nil)
        #expect(service.result.totalRowCount == 6)
    }

    @Test func appendAlignsColumnsAndExportIncludesBeyondPreview() async throws {
        let folder = try fixtures()
        defer { try? FileManager.default.removeItem(at: folder) }
        let engine = DuckDBDataEngine()
        let orders = try await importSource("orders", folder: folder, engine: engine)
        let customers = try await importSource("customers", folder: folder, engine: engine)
        var c = DataWorkflowConfiguration(); c.leftID = orders.id
        let workflow = try DataWorkflowBuilder.build(mode: .combine, configuration: c, sources: [orders, customers])
        let result = try await engine.query(workflow.plan.sql, limit: 1)
        #expect(result.totalRowCount == 5)
        #expect(result.rows.count == 1)
        let url = folder.appendingPathComponent("export.csv")
        try await engine.exportCSV(query: workflow.plan.sql, to: url)
        let exported = try await engine.registerCSV(url, id: UUID(), tableName: "exported")
        #expect(exported.rowCount == 5)
        #expect(exported.columns.contains { $0.name == "_tidy_source" })
    }
}
