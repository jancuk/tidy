import AppKit
import SwiftUI

struct AskAIMarkdown: View {
    let content: String
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(AskAIMarkdownBlock.parse(content).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }.font(.system(size: 14)).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
                ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") ? .systemAction(url) : .discarded
            })
    }

    @ViewBuilder private func blockView(_ block: AskAIMarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text)).font(.system(size: level == 1 ? 23 : level == 2 ? 19 : 16, weight: .semibold)).padding(.top, 5)
        case .paragraph(let text): Text(inline(text))
        case .quote(let text):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(WorkspaceDesign.border).frame(width: 3)
                Text(inline(text)).foregroundStyle(.secondary)
            }.fixedSize(horizontal: false, vertical: true)
        case .list(let items, let start):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(start.map { "\($0 + index)." } ?? "•").foregroundStyle(.secondary).frame(minWidth: 16, alignment: .trailing)
                        Text(inline(item))
                    }
                }
            }
        case .code(let language, let code): AskAICodeBlock(language: language, code: code)
        case .table(let headings, let rows):
            ScrollView(.horizontal) {
                Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ForEach(Array(headings.enumerated()), id: \.offset) { _, heading in
                            Text(inline(heading)).fontWeight(.semibold).padding(10).frame(minWidth: 100, alignment: .leading)
                        }
                    }.background(WorkspaceDesign.inset)
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        GridRow {
                            ForEach(headings.indices, id: \.self) { column in
                                Text(inline(column < row.count ? row[column] : "")).padding(10).frame(minWidth: 100, alignment: .leading)
                            }
                        }.background(index.isMultiple(of: 2) ? WorkspaceDesign.surface : WorkspaceDesign.canvas)
                    }
                }.font(.system(size: 12))
            }.clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WorkspaceDesign.border))
        case .rule: Divider()
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

private struct AskAICodeBlock: View {
    let language: String
    let code: String
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "Code" : language).font(.system(size: 10, weight: .medium, design: .monospaced))
                Spacer()
                Button {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string); copied = true
                } label: { Label(copied ? "Copied" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(.plain).font(.system(size: 10)).help("Copy code without the Markdown fence")
                    .task(id: copied) { if copied { try? await Task.sleep(for: .seconds(2)); copied = false } }
            }.foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            ScrollView(.horizontal) {
                Text(code).font(.system(size: 12, design: .monospaced)).lineSpacing(5).textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false).padding(16)
            }
        }.background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WorkspaceDesign.border))
    }
}

enum AskAIMarkdownBlock: Equatable {
    case heading(Int, String)
    case paragraph(String)
    case quote(String)
    case list([String], start: Int?)
    case code(language: String, content: String)
    case table(headings: [String], rows: [[String]])
    case rule

    static func parse(_ content: String) -> [Self] {
        let lines = content.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [Self] = []
        var index = 0
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
        }
        while index < lines.count {
            let raw = lines[index]
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); index += 1; continue }
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                flush()
                let marker = line.first!
                let length = line.prefix(while: { $0 == marker }).count
                let language = String(line.dropFirst(length)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    let prefix = candidate.prefix(while: { $0 == marker })
                    if prefix.count >= length && candidate.dropFirst(prefix.count).isEmpty { index += 1; break }
                    code.append(lines[index]); index += 1
                }
                blocks.append(.code(language: language, content: code.joined(separator: "\n"))); continue
            }
            if line.contains("|"), index + 1 < lines.count {
                let separator = cells(lines[index + 1])
                if !separator.isEmpty && separator.allSatisfy({ $0.range(of: "^:?-{3,}:?$", options: .regularExpression) != nil }) {
                    flush()
                    let headings = cells(line)
                    index += 2
                    var rows: [[String]] = []
                    while index < lines.count, lines[index].contains("|"), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                        rows.append(cells(lines[index])); index += 1
                    }
                    blocks.append(.table(headings: headings, rows: rows)); continue
                }
            }
            let hashes = line.prefix(while: { $0 == "#" }).count
            if (1...6).contains(hashes), line.dropFirst(hashes).first == " " {
                flush(); blocks.append(.heading(hashes, String(line.dropFirst(hashes + 1)))); index += 1; continue
            }
            if ["---", "***", "___"].contains(line) { flush(); blocks.append(.rule); index += 1; continue }
            if line.hasPrefix(">") {
                flush(); var quote: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quote.append(String(lines[index].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces)); index += 1
                }
                blocks.append(.quote(quote.joined(separator: "\n"))); continue
            }
            if let first = listItem(line) {
                flush(); var items = [first.text]; index += 1
                while index < lines.count, let next = listItem(lines[index].trimmingCharacters(in: .whitespaces)), (first.start == nil) == (next.start == nil) {
                    items.append(next.text); index += 1
                }
                blocks.append(.list(items, start: first.start)); continue
            }
            if raw.hasPrefix("    ") || raw.hasPrefix("\t") {
                flush(); var code: [String] = []
                while index < lines.count, lines[index].hasPrefix("    ") || lines[index].hasPrefix("\t") {
                    code.append(String(lines[index].dropFirst(lines[index].hasPrefix("\t") ? 1 : 4))); index += 1
                }
                blocks.append(.code(language: "", content: code.joined(separator: "\n"))); continue
            }
            paragraph.append(line); index += 1
        }
        flush()
        return blocks
    }

    private static func listItem(_ line: String) -> (text: String, start: Int?)? {
        if ["- ", "* ", "+ "].contains(where: line.hasPrefix) { return (String(line.dropFirst(2)), nil) }
        let digits = line.prefix(while: \.isNumber)
        let remaining = line.dropFirst(digits.count)
        if digits.count <= 9, let start = Int(digits), remaining.hasPrefix(". ") || remaining.hasPrefix(") ") {
            return (String(remaining.dropFirst(2)), start)
        }
        return nil
    }

    private static func cells(_ line: String) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("|") { text.removeFirst() }
        if text.hasSuffix("|") { text.removeLast() }
        return text.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
