import Foundation
import Testing
@testable import Tidy

struct DataTableBrowsingTests {
    @Test func filtersTreatSearchAsLiteralAndHandleBlankCells() async throws {
        let engine = DuckDBDataEngine()
        let source = try await engine.registerQuery("""
        SELECT * FROM (VALUES ('001', 'O''Brien_100%', '10'), ('002', 'other', '2'),
            ('003', NULL, 'bad'), ('004', '', NULL)) t("odd""id", name, amount)
        """, id: UUID(), tableName: "filters", displayName: "Filters")
        let base = DataQueryBuilder.preview(tableName: source.tableName)
        let columns = source.columns.map(\.name)
        var options = DataTableOptions()
        options.search = "O'Brien_100%"
        var sql = try DataTableQueryBuilder.build(baseSQL: base, columns: columns, options: options)
        #expect(try await engine.query(sql, limit: 10).rows.first?.first == "001")
        options.search = "' OR TRUE --"
        sql = try DataTableQueryBuilder.build(baseSQL: base, columns: columns, options: options)
        #expect(try await engine.query(sql, limit: 10).totalRowCount == 0)
        options.search = ""
        options.filters = [DataColumnFilter(column: "name", operation: .isEmpty)]
        sql = try DataTableQueryBuilder.build(baseSQL: base, columns: columns, options: options)
        #expect(try await engine.query(sql, limit: 10).totalRowCount == 2)
        options.filters = [DataColumnFilter(column: "odd\"id", operation: .equals, value: "001"),
                           DataColumnFilter(column: "amount", operation: .lessThan, value: "5")]
        sql = try DataTableQueryBuilder.build(baseSQL: base, columns: columns, options: options)
        #expect(try await engine.query(sql, limit: 10).totalRowCount == 0)
        options.matchAny = true
        options.sorts = [DataColumnSort(column: "amount", kind: .number)]
        sql = try DataTableQueryBuilder.build(baseSQL: base, columns: columns, options: options)
        #expect(try await engine.query(sql, limit: 10).rows.map { $0[0] } == ["002", "001"])
        options.filters = [DataColumnFilter(column: "amount", operation: .greaterThan, value: "nan")]
        #expect(throws: DataWorkspaceError.self) {
            try DataTableQueryBuilder.build(baseSQL: base, columns: columns, options: options)
        }
    }

    @Test func multiSortUsesNumbersDatesAndNullsLast() async throws {
        let engine = DuckDBDataEngine()
        let source = try await engine.registerQuery("""
        SELECT * FROM (VALUES ('a', '2', '2026-09-02'), ('a', '10', '2026-09-01'),
        ('a', '10', '2026-09-03'), ('a', 'bad', 'invalid'), ('b', NULL, NULL)) t(team, amount, day)
        """, id: UUID(), tableName: "sorting", displayName: "Sorting")
        var options = DataTableOptions()
        options.sorts = [DataColumnSort(column: "team"), DataColumnSort(column: "amount", ascending: false, kind: .number),
                         DataColumnSort(column: "day", ascending: false, kind: .date)]
        let sql = try DataTableQueryBuilder.build(baseSQL: "SELECT * FROM sorting", columns: source.columns.map(\.name), options: options)
        let result = try await engine.query(sql, limit: 10)
        #expect(result.rows == [["a", "10", "2026-09-03"], ["a", "10", "2026-09-01"],
                               ["a", "2", "2026-09-02"], ["a", "bad", "invalid"], ["b", nil, nil]])
    }

    @Test @MainActor func browsingFiltersAllRowsPagesExportsAndRecoversFromErrors() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let csv = "id,amount,status\n" + (0..<1200).map { "\(String(format: "%05d", $0)),\($0),\($0.isMultiple(of: 2) ? "paid" : "pending")\n" }.joined()
        let url = folder.appendingPathComponent("rows.csv")
        try Data(csv.utf8).write(to: url)
        let suite = "TidyBrowsingTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = DataWorkspaceService(logStore: AIRequestLogStore(), defaults: defaults)
        await service.addCSVs([url])
        #expect(service.result.rows.count == 250)
        var options = DataTableOptions()
        options.filters = [DataColumnFilter(column: "status", operation: .equals, value: "PAID")]
        options.sorts = [DataColumnSort(column: "amount", ascending: false, kind: .number)]
        options.hiddenColumns = ["status"]
        await service.applyTableOptions(options)
        #expect(service.errorMessage == nil)
        #expect(service.result.totalRowCount == 600)
        #expect(service.result.rows.first?[0] == "01198")
        await service.changePage(forward: true)
        #expect(service.pageOffset == 250)
        #expect(service.result.rows.first?[0] == "00698")
        await service.changePage(forward: true)
        #expect(service.result.rows.count == 100)
        #expect(!service.hasNextPage)
        await service.changePage(forward: false)
        #expect(service.pageOffset == 250)
        let exported = folder.appendingPathComponent("export.csv")
        await service.exportCurrentResult(to: exported)
        let text = try String(contentsOf: exported, encoding: .utf8)
        #expect(text.split(separator: "\n").count == 601)
        #expect(text.hasPrefix("id,amount,status\n01198,1198,paid\n"))
        var invalid = options
        invalid.filters = [DataColumnFilter(column: "missing")]
        await service.applyTableOptions(invalid)
        #expect(service.errorMessage != nil)
        #expect(service.tableOptions == options)
        #expect(service.pageOffset == 250)
        #expect(service.canExport)
        await service.applyTableOptions(DataTableOptions())
        #expect(service.pageOffset == 0)
        #expect(service.result.totalRowCount == 1200)
        #expect(service.errorMessage == nil)
        await service.selectSource(try #require(service.selectedSource))
        #expect(!service.tableOptions.isActive)
        service.changeMode(.replace)
        service.configuration.valueColumn = "status"
        service.configuration.find = "paid"
        service.configuration.replacement = "settled"
        await service.runWorkflow()
        options.filters = [DataColumnFilter(column: "status", operation: .equals, value: "settled")]
        await service.applyTableOptions(options)
        await service.useResultAsSource()
        #expect(service.selectedSource?.rowCount == 600)
        #expect(service.selectedSource?.columns.contains { $0.name == "result_status" } == true)
        #expect(service.result.rows.first?[0] == "01198")
        #expect(!service.tableOptions.isActive)
    }

    @Test func tiedSortKeysDoNotSkipOrRepeatRowsAcrossPages() async throws {
        let engine = DuckDBDataEngine()
        let source = try await engine.registerQuery(
            "SELECT i::VARCHAR AS id, (i % 3)::VARCHAR AS category FROM range(1000) t(i)",
            id: UUID(), tableName: "ties", displayName: "Ties"
        )
        var options = DataTableOptions()
        options.sorts = [DataColumnSort(column: "category")]
        let sql = try DataTableQueryBuilder.build(baseSQL: "SELECT * FROM ties", columns: source.columns.map(\.name), options: options)
        var ids: [String] = []
        for offset in stride(from: 0, to: 1000, by: 250) {
            let page = try await engine.queryPage(sql, limit: 250, offset: offset, knownTotal: 1000)
            ids += page.rows.compactMap { $0[0] }
        }
        #expect(ids.count == 1000)
        #expect(Set(ids).count == 1000)
        let repeated = try await engine.queryPage(sql, limit: 250, offset: 250, knownTotal: 1000)
        #expect(repeated.rows.compactMap { $0[0] } == Array(ids[250..<500]))
    }

    @Test func largeCSVImportRetainsLateQuotedFieldsAndMeasuresBrowsing() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("large.csv")
        let payload = String(repeating: "sample text ", count: 16)
        var csv = "id,amount,group_name,notes\n"
        for index in 0..<60_000 {
            let notes = index == 59_999 ? "\"late, quoted\nsecond line\"" : payload
            csv += "\(String(format: "%06d", index)),\(index),group\(index % 10),\(notes)\n"
        }
        let data = Data(csv.utf8)
        #expect(data.count > 2_000_000)
        try data.write(to: url)
        let engine = DuckDBDataEngine()
        let clock = ContinuousClock()
        let start = clock.now
        let source = try await engine.registerCSV(url, id: UUID(), tableName: "large")
        let importDuration = start.duration(to: clock.now)
        #expect(source.rowCount == 60_000)
        let previewStart = clock.now
        let preview = try await engine.queryPage("SELECT * FROM large", limit: 250, offset: 0, knownTotal: source.rowCount)
        let previewDuration = previewStart.duration(to: clock.now)
        #expect(preview.rows.count == 250)
        #expect(preview.rows[0][0] == "000000")
        var options = DataTableOptions()
        options.filters = [DataColumnFilter(column: "group_name", operation: .equals, value: "group9")]
        options.sorts = [DataColumnSort(column: "amount", ascending: false, kind: .number)]
        let sql = try DataTableQueryBuilder.build(baseSQL: "SELECT * FROM large", columns: source.columns.map(\.name), options: options)
        let filterStart = clock.now
        let filtered = try await engine.query(sql, limit: 250)
        let filterDuration = filterStart.duration(to: clock.now)
        #expect(filtered.totalRowCount == 6_000)
        #expect(filtered.rows.first?[3] == "late, quoted\nsecond line")
        let pageStart = clock.now
        let page = try await engine.queryPage(sql, limit: 250, offset: 250, knownTotal: filtered.totalRowCount)
        let pageDuration = pageStart.duration(to: clock.now)
        #expect(page.rows.first?[0] == "057499")
        print("Tidy Data benchmark: \(data.count) bytes, 60000 rows; import \(importDuration), preview \(previewDuration), filter/sort \(filterDuration), next page \(pageDuration)")
    }
}
