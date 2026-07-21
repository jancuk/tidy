import Foundation

struct ToolResult {
    let output: String
    let status: String
    let isError: Bool

    static func success(_ output: String, status: String = "Ready") -> ToolResult {
        ToolResult(output: output, status: status, isError: false)
    }

    static func failure(_ message: String) -> ToolResult {
        ToolResult(output: message, status: message, isError: true)
    }
}

enum JSONTool {
    static func format(_ input: String, minified: Bool = false) -> ToolResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .success("", status: "Paste JSON to format or validate.")
        }

        do {
            let object = try JSONSerialization.jsonObject(
                with: Data(trimmed.utf8),
                options: [.fragmentsAllowed]
            )
            let options: JSONSerialization.WritingOptions = minified ? [.withoutEscapingSlashes] : [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try JSONSerialization.data(withJSONObject: object, options: options)
            let output = String(decoding: data, as: UTF8.self)
            return .success(output, status: "Valid JSON")
        } catch {
            return .failure("Invalid JSON: \(error.localizedDescription)")
        }
    }
}

struct JWTDebugResult {
    let headerJSON: String
    let payloadJSON: String
    let signature: String
    let claims: [(String, String)]
    let status: String
    let isError: Bool
}

enum JWTTool {
    static func decode(_ token: String) -> JWTDebugResult {
        let parts = token.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".").map(String.init)
        guard parts.count == 3 else {
            return JWTDebugResult(headerJSON: "", payloadJSON: "", signature: "", claims: [], status: "JWT must have header, payload, and signature.", isError: true)
        }

        guard
            let headerData = base64URLDecode(parts[0]),
            let payloadData = base64URLDecode(parts[1])
        else {
            return JWTDebugResult(headerJSON: "", payloadJSON: "", signature: parts.last ?? "", claims: [], status: "JWT contains invalid Base64URL data.", isError: true)
        }

        let header = prettyJSON(from: headerData)
        let payload = prettyJSON(from: payloadData)
        let claims = claimsSummary(from: payloadData)
        return JWTDebugResult(
            headerJSON: header ?? String(decoding: headerData, as: UTF8.self),
            payloadJSON: payload ?? String(decoding: payloadData, as: UTF8.self),
            signature: parts[2],
            claims: claims,
            status: "Decoded JWT. Signature is shown but not verified.",
            isError: false
        )
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }

    private static func prettyJSON(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func claimsSummary(from data: Data) -> [(String, String)] {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let dateClaims: Set<String> = ["exp", "iat", "nbf"]
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium

        return payload.keys.sorted().map { key in
            let value = payload[key]
            if dateClaims.contains(key), let seconds = value as? TimeInterval {
                return (key, formatter.string(from: Date(timeIntervalSince1970: seconds)))
            }
            if let string = value as? String {
                return (key, string)
            }
            if JSONSerialization.isValidJSONObject([value as Any]),
               let data = try? JSONSerialization.data(withJSONObject: value as Any, options: [.withoutEscapingSlashes]) {
                return (key, String(decoding: data, as: UTF8.self))
            }
            return (key, String(describing: value ?? "null"))
        }
    }
}

struct UnixTimeResult {
    let local: String
    let utc: String
    let iso8601: String
    let seconds: Int
    let milliseconds: Int64
}

enum UnixTimeConversionResult {
    case success(UnixTimeResult)
    case failure(String)
}

enum UnixTimeTool {
    static func convert(_ input: String, now: Date = Date()) -> UnixTimeConversionResult {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(Int(now.timeIntervalSince1970))
            : input.filter { $0.isNumber || $0 == "." || $0 == "-" }

        guard let raw = Double(cleaned) else {
            return .failure("Enter a Unix timestamp in seconds or milliseconds.")
        }

        let secondsValue = abs(raw) > 9_999_999_999 ? raw / 1_000 : raw
        let date = Date(timeIntervalSince1970: secondsValue)
        let localFormatter = DateFormatter()
        localFormatter.dateStyle = .full
        localFormatter.timeStyle = .medium

        let utcFormatter = DateFormatter()
        utcFormatter.dateStyle = .full
        utcFormatter.timeStyle = .medium
        utcFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return .success(UnixTimeResult(
            local: localFormatter.string(from: date),
            utc: utcFormatter.string(from: date),
            iso8601: iso.string(from: date),
            seconds: Int(secondsValue),
            milliseconds: Int64(secondsValue * 1_000)
        ))
    }
}

enum CSVTool {
    static func csvToJSON(_ input: String) -> ToolResult {
        do {
            let rows = try parse(input)
            guard let header = rows.first, !header.isEmpty else {
                return .success("[]", status: "No CSV rows found.")
            }

            let objects = rows.dropFirst().filter { !$0.allSatisfy(\.isEmpty) }.map { row in
                Dictionary(uniqueKeysWithValues: header.enumerated().map { index, key in
                    (key, index < row.count ? row[index] : "")
                })
            }
            let data = try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            return .success(String(decoding: data, as: UTF8.self), status: "Converted \(objects.count) rows to JSON.")
        } catch {
            return .failure("CSV error: \(error.localizedDescription)")
        }
    }

    static func jsonToCSV(_ input: String) -> ToolResult {
        do {
            let json = try JSONSerialization.jsonObject(with: Data(input.utf8), options: [.fragmentsAllowed])
            let objects: [[String: Any]]
            if let array = json as? [[String: Any]] {
                objects = array
            } else if let object = json as? [String: Any] {
                objects = [object]
            } else {
                return .failure("JSON must be an object or an array of objects.")
            }

            var headers: [String] = []
            for object in objects {
                for key in object.keys.sorted() where !headers.contains(key) {
                    headers.append(key)
                }
            }

            let lines = [headers.map(escape).joined(separator: ",")] + objects.map { object in
                headers.map { key in
                    stringify(object[key]).map(escape) ?? ""
                }.joined(separator: ",")
            }
            return .success(lines.joined(separator: "\n"), status: "Converted \(objects.count) JSON records to CSV.")
        } catch {
            return .failure("JSON error: \(error.localizedDescription)")
        }
    }

    private static func parse(_ input: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = input.makeIterator()

        while let character = iterator.next() {
            if character == "\"" {
                if inQuotes, let next = iterator.next() {
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        inQuotes = false
                        if next == "," {
                            row.append(field)
                            field = ""
                        } else if next == "\n" {
                            row.append(field)
                            rows.append(row)
                            row = []
                            field = ""
                        } else if next != "\r" {
                            field.append(next)
                        }
                    }
                } else {
                    inQuotes.toggle()
                }
            } else if character == ",", !inQuotes {
                row.append(field)
                field = ""
            } else if character == "\n", !inQuotes {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else if character != "\r" {
                field.append(character)
            }
        }

        row.append(field)
        if !row.allSatisfy(\.isEmpty) {
            rows.append(row)
        }
        return rows
    }

    private static func stringify(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes]) {
            return String(decoding: data, as: UTF8.self)
        }
        return String(describing: value)
    }

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}

enum DiffKind {
    case unchanged
    case added
    case removed
}

struct DiffRow: Identifiable {
    let id = UUID()
    let kind: DiffKind
    let text: String
}

enum TextDiffTool {
    static func lineDiff(old: String, new: String) -> [DiffRow] {
        let oldLines = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let m = oldLines.count
        let n = newLines.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        if m > 0 && n > 0 {
            for i in stride(from: m - 1, through: 0, by: -1) {
                for j in stride(from: n - 1, through: 0, by: -1) {
                    if oldLines[i] == newLines[j] {
                        dp[i][j] = dp[i + 1][j + 1] + 1
                    } else {
                        dp[i][j] = max(dp[i + 1][j], dp[i][j + 1])
                    }
                }
            }
        }

        var rows: [DiffRow] = []
        var i = 0
        var j = 0
        while i < m && j < n {
            if oldLines[i] == newLines[j] {
                rows.append(DiffRow(kind: .unchanged, text: oldLines[i]))
                i += 1
                j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                rows.append(DiffRow(kind: .removed, text: oldLines[i]))
                i += 1
            } else {
                rows.append(DiffRow(kind: .added, text: newLines[j]))
                j += 1
            }
        }
        while i < m {
            rows.append(DiffRow(kind: .removed, text: oldLines[i]))
            i += 1
        }
        while j < n {
            rows.append(DiffRow(kind: .added, text: newLines[j]))
            j += 1
        }
        return rows
    }
}

enum DelimiterQuoteStyle: String, CaseIterable, Identifiable {
    case none = "Plain"
    case double = "Double quotes"
    case single = "Single quotes"

    var id: String { rawValue }
}

enum DelimiterTool {
    static func convert(
        _ input: String,
        delimiter: String,
        quoteStyle: DelimiterQuoteStyle
    ) -> ToolResult {
        let values = input
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !values.isEmpty else {
            return .success("", status: "Enter one value per line.")
        }

        let output = values
            .map { wrap($0, style: quoteStyle) }
            .joined(separator: delimiter)
        let noun = values.count == 1 ? "value" : "values"
        return .success(output, status: "Converted \(values.count) \(noun).")
    }

    private static func wrap(_ value: String, style: DelimiterQuoteStyle) -> String {
        switch style {
        case .none:
            return value
        case .double:
            return "\"\(escape(value, quote: "\""))\""
        case .single:
            return "'\(escape(value, quote: "'"))'"
        }
    }

    private static func escape(_ value: String, quote: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: quote, with: "\\\(quote)")
    }
}

struct CronParseResult {
    let description: String
    let fields: [(String, String)]
    let nextRuns: [String]
    let status: String
    let isError: Bool
}

enum CronTool {
    static func parse(_ expression: String, from startDate: Date = Date()) -> CronParseResult {
        let parts = expression.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 5 else {
            return CronParseResult(description: "", fields: [], nextRuns: [], status: "Use five fields: minute hour day month weekday.", isError: true)
        }

        do {
            let minute = try CronField.parse(parts[0], range: 0...59)
            let hour = try CronField.parse(parts[1], range: 0...23)
            let day = try CronField.parse(parts[2], range: 1...31)
            let month = try CronField.parse(parts[3], range: 1...12, names: monthNames)
            let weekday = try CronField.parse(parts[4], range: 0...7, names: weekdayNames)

            let fields = [
                ("Minutes", minute.summary),
                ("Hours", hour.summary),
                ("Day of Month", day.summary),
                ("Months", month.summary),
                ("Day of Week", weekday.summary)
            ]
            let next = nextRuns(minute: minute.values, hour: hour.values, day: day.values, month: month.values, weekday: weekday.values, from: startDate)
            return CronParseResult(
                description: describe(minute: parts[0], hour: parts[1]),
                fields: fields,
                nextRuns: next,
                status: "Parsed cron expression.",
                isError: false
            )
        } catch {
            return CronParseResult(description: "", fields: [], nextRuns: [], status: error.localizedDescription, isError: true)
        }
    }

    private static let monthNames = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12
    ]

    private static let weekdayNames = [
        "sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6
    ]

    private static func describe(minute: String, hour: String) -> String {
        if minute == "*" && hour == "*" { return "Every minute" }
        if minute.hasPrefix("*/"), hour == "*" { return "Every \(minute.dropFirst(2)) minutes" }
        if minute.hasPrefix("*/") { return "Every \(minute.dropFirst(2)) minutes during hour(s) \(hour)" }
        if hour == "*" { return "Every hour at minute \(minute)" }
        return "At \(hour):\(minute.count == 1 ? "0\(minute)" : minute)"
    }

    private static func nextRuns(minute: Set<Int>, hour: Set<Int>, day: Set<Int>, month: Set<Int>, weekday: Set<Int>, from startDate: Date) -> [String] {
        var calendar = Calendar.current
        calendar.timeZone = .current
        var date = calendar.date(byAdding: .minute, value: 1, to: startDate) ?? startDate
        date = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)) ?? date
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var matches: [String] = []
        for _ in 0..<(366 * 24 * 60) {
            let components = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: date)
            let cronWeekday = (components.weekday ?? 1) - 1
            if minute.contains(components.minute ?? -1),
               hour.contains(components.hour ?? -1),
               day.contains(components.day ?? -1),
               month.contains(components.month ?? -1),
               (weekday.contains(cronWeekday) || (cronWeekday == 0 && weekday.contains(7))) {
                matches.append(formatter.string(from: date))
                if matches.count == 5 { break }
            }
            date = calendar.date(byAdding: .minute, value: 1, to: date) ?? date
        }
        return matches
    }
}

private struct CronField {
    let values: Set<Int>
    let range: ClosedRange<Int>

    var summary: String {
        if values.count == range.count { return "(All)" }
        return values.sorted().map(String.init).joined(separator: ", ")
    }

    static func parse(_ field: String, range: ClosedRange<Int>, names: [String: Int] = [:]) throws -> CronField {
        var values = Set<Int>()
        for part in field.lowercased().split(separator: ",").map(String.init) {
            let stepParts = part.split(separator: "/", maxSplits: 1).map(String.init)
            let base = stepParts[0]
            let step = stepParts.count == 2 ? Int(stepParts[1]) : nil
            if step == 0 {
                throw CronError.invalid("Step cannot be zero in '\(field)'.")
            }

            let baseRange: ClosedRange<Int>
            if base == "*" {
                baseRange = range
            } else if base.contains("-") {
                let bounds = base.split(separator: "-", maxSplits: 1).map(String.init)
                guard bounds.count == 2,
                      let lower = resolve(bounds[0], names: names),
                      let upper = resolve(bounds[1], names: names),
                      lower <= upper
                else {
                    throw CronError.invalid("Invalid range '\(base)'.")
                }
                baseRange = lower...upper
            } else if let value = resolve(base, names: names) {
                baseRange = value...value
            } else {
                throw CronError.invalid("Invalid field '\(field)'.")
            }

            for value in baseRange where range.contains(value) {
                if let step {
                    if (value - baseRange.lowerBound) % step == 0 {
                        values.insert(value)
                    }
                } else {
                    values.insert(value)
                }
            }
        }

        guard !values.isEmpty else {
            throw CronError.invalid("Field '\(field)' has no matching values.")
        }
        return CronField(values: values, range: range)
    }

    private static func resolve(_ value: String, names: [String: Int]) -> Int? {
        if let number = Int(value) { return number }
        return names[value]
    }
}

private enum CronError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        }
    }
}
