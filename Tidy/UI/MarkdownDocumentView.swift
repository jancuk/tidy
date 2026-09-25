import AppKit
import SwiftUI

struct MarkdownListItem: Equatable {
    var text: String
    var depth: Int
    var number: Int?
    var checked: Bool?
}

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case quote(String)
    case list([MarkdownListItem])
    case code(language: String, content: String)
    case table(headings: [String], rows: [[String]])
    case image(alt: String, url: String)
    case rule
}

enum MarkdownDocument {
    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }

        while index < lines.count {
            let raw = lines[index]
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
                index += 1
                continue
            }
            if let fence = fenceStart(line) {
                flushParagraph()
                var code: [String] = []
                index += 1
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidate.hasPrefix(fence.marker), candidate.dropFirst(fence.marker.count).trimmingCharacters(in: .whitespaces).isEmpty {
                        index += 1
                        break
                    }
                    code.append(lines[index])
                    index += 1
                }
                blocks.append(.code(language: fence.language, content: code.joined(separator: "\n")))
                continue
            }
            if line.contains("|"), index + 1 < lines.count, isTableSeparator(lines[index + 1]) {
                flushParagraph()
                let headings = tableCells(line)
                var rows: [[String]] = []
                index += 2
                while index < lines.count, lines[index].contains("|"), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(tableCells(lines[index]))
                    index += 1
                }
                blocks.append(.table(headings: headings, rows: rows))
                continue
            }
            if let heading = atxHeading(line) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }
            if index + 1 < lines.count, let level = setextLevel(lines[index + 1]), !line.isEmpty {
                flushParagraph()
                blocks.append(.heading(level: level, text: line))
                index += 2
                continue
            }
            if isRule(line) {
                flushParagraph()
                blocks.append(.rule)
                index += 1
                continue
            }
            if let image = standaloneImage(line) {
                flushParagraph()
                blocks.append(.image(alt: image.alt, url: image.url))
                index += 1
                continue
            }
            if line.hasPrefix(">") {
                flushParagraph()
                var quote: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quote.append(String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quote.joined(separator: "\n")))
                continue
            }
            if let first = listItem(raw) {
                flushParagraph()
                var items = [first]
                index += 1
                while index < lines.count, let item = listItem(lines[index]) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.list(items))
                continue
            }
            if raw.hasPrefix("    ") || raw.hasPrefix("\t") {
                flushParagraph()
                var code: [String] = []
                while index < lines.count, lines[index].hasPrefix("    ") || lines[index].hasPrefix("\t") {
                    code.append(String(lines[index].dropFirst(lines[index].hasPrefix("\t") ? 1 : 4)))
                    index += 1
                }
                blocks.append(.code(language: "", content: code.joined(separator: "\n")))
                continue
            }
            paragraph.append(line)
            index += 1
        }
        flushParagraph()
        return blocks
    }

    static func plainTitle(from source: String) -> String {
        guard let first = source.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return "Untitled note"
        }
        var value = first.trimmingCharacters(in: .whitespaces)
        if let heading = atxHeading(value) { value = heading.text }
        if value.hasPrefix(">") { value = String(value.dropFirst()).trimmingCharacters(in: .whitespaces) }
        if let item = listItem(value) { value = item.text }
        if let image = standaloneImage(value) { value = image.alt }
        let attributed = try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        let plain = attributed.map { String($0.characters) } ?? value
        return String((plain.isEmpty ? "Untitled note" : plain).prefix(120))
    }

    private static func fenceStart(_ line: String) -> (marker: String, language: String)? {
        guard line.hasPrefix("```") || line.hasPrefix("~~~") else { return nil }
        let character = line.first!
        let marker = String(line.prefix(while: { $0 == character }))
        return (marker, String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces))
    }

    private static func atxHeading(_ line: String) -> (level: Int, text: String)? {
        let count = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(count), line.dropFirst(count).first == " " else { return nil }
        var text = String(line.dropFirst(count + 1)).trimmingCharacters(in: .whitespaces)
        while text.last == "#" { text.removeLast() }
        return (count, text.trimmingCharacters(in: .whitespaces))
    }

    private static func setextLevel(_ line: String) -> Int? {
        let value = line.trimmingCharacters(in: .whitespaces)
        guard value.count >= 2 else { return nil }
        if value.allSatisfy({ $0 == "=" }) { return 1 }
        if value.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    private static func isRule(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let marker = compact.first, ["-", "*", "_"].contains(marker) else { return false }
        return compact.allSatisfy { $0 == marker }
    }

    private static func listItem(_ raw: String) -> MarkdownListItem? {
        let spaces = raw.prefix(while: { $0 == " " || $0 == "\t" })
        let depth = spaces.reduce(0) { $0 + ($1 == "\t" ? 1 : 0) } + spaces.filter { $0 == " " }.count / 2
        let line = raw.dropFirst(spaces.count)
        if ["- ", "* ", "+ "].contains(where: line.hasPrefix) {
            var text = String(line.dropFirst(2))
            var checked: Bool?
            let lowered = text.lowercased()
            if lowered.hasPrefix("[ ] ") { checked = false; text = String(text.dropFirst(4)) }
            else if lowered.hasPrefix("[x] ") { checked = true; text = String(text.dropFirst(4)) }
            return MarkdownListItem(text: text, depth: depth, number: nil, checked: checked)
        }
        let digits = line.prefix(while: { $0.isNumber })
        let remaining = line.dropFirst(digits.count)
        guard digits.count <= 9, let number = Int(digits), remaining.hasPrefix(". ") || remaining.hasPrefix(") ") else { return nil }
        return MarkdownListItem(text: String(remaining.dropFirst(2)), depth: depth, number: number, checked: nil)
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let cells = tableCells(line)
        return !cells.isEmpty && cells.allSatisfy { $0.range(of: "^:?-{3,}:?$", options: .regularExpression) != nil }
    }

    private static func tableCells(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func standaloneImage(_ line: String) -> (alt: String, url: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"^!\[([^\]]*)\]\((\S+?)(?:\s+[\"'][^\"']*[\"'])?\)$"#),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges == 3,
              let altRange = Range(match.range(at: 1), in: line), let urlRange = Range(match.range(at: 2), in: line) else { return nil }
        return (String(line[altRange]), String(line[urlRange]))
    }
}

struct MarkdownDocumentView: View {
    let source: String
    var compact = false

    private var visibleBlocks: [MarkdownBlock] {
        let blocks = MarkdownDocument.parse(source)
        return compact ? Array(blocks.prefix(2)) : blocks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 14) {
            ForEach(Array(visibleBlocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            guard !compact, ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return .discarded }
            return .systemAction(url)
        })
    }

    @ViewBuilder private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(.system(size: compact ? headingSize(level) * 0.72 : headingSize(level), weight: .semibold, design: level <= 2 ? .serif : .default))
                .lineLimit(compact ? 2 : nil)
        case .paragraph(let text):
            Text(inline(text)).font(.system(size: compact ? 13 : 15)).lineSpacing(5).lineLimit(compact ? 2 : nil)
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.55)).frame(width: 3)
                Text(inline(text)).font(.system(size: compact ? 13 : 15)).italic().foregroundStyle(.secondary)
                    .lineLimit(compact ? 2 : nil)
            }
        case .list(let items):
            VStack(alignment: .leading, spacing: compact ? 3 : 7) {
                ForEach(Array(items.prefix(compact ? 2 : items.count).enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        listMarker(item).frame(width: 18, alignment: .trailing)
                        Text(inline(item.text)).lineLimit(compact ? 1 : nil)
                    }
                    .font(.system(size: compact ? 13 : 15))
                    .padding(.leading, CGFloat(item.depth) * 18)
                }
            }
        case .code(let language, let content):
            VStack(alignment: .leading, spacing: 7) {
                if !language.isEmpty && !compact { Text(language).font(.caption2).foregroundStyle(.secondary) }
                Text(content).font(.system(size: compact ? 12 : 13, design: .monospaced)).lineSpacing(4)
                    .lineLimit(compact ? 2 : nil)
            }
            .padding(compact ? 8 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WorkspaceDesign.inset, in: RoundedRectangle(cornerRadius: 9))
        case .table(let headings, let rows):
            ScrollView(.horizontal) {
                Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ForEach(Array(headings.enumerated()), id: \.offset) { _, heading in
                            Text(inline(heading)).fontWeight(.semibold).padding(8).frame(minWidth: 90, alignment: .leading)
                        }
                    }.background(WorkspaceDesign.inset)
                    ForEach(Array(rows.prefix(compact ? 1 : rows.count).enumerated()), id: \.offset) { index, row in
                        GridRow {
                            ForEach(headings.indices, id: \.self) { column in
                                Text(inline(column < row.count ? row[column] : "")).padding(8).frame(minWidth: 90, alignment: .leading)
                            }
                        }.background(index.isMultiple(of: 2) ? WorkspaceDesign.surface : WorkspaceDesign.canvas)
                    }
                }.font(.system(size: compact ? 11 : 13))
            }
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(WorkspaceDesign.border))
        case .image(let alt, let url):
            if !compact, let imageURL = Self.safeImageURL(url) {
                RemoteMarkdownImage(alt: alt, url: imageURL)
            } else {
                Label(alt.isEmpty ? "Image" : alt, systemImage: "photo").font(.caption).foregroundStyle(.secondary)
            }
        case .rule:
            Divider()
        }
    }

    @ViewBuilder private func listMarker(_ item: MarkdownListItem) -> some View {
        if let checked = item.checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square").foregroundStyle(checked ? Color.accentColor : Color.secondary)
        } else if let number = item.number {
            Text("\(number).").foregroundStyle(.secondary)
        } else {
            Text("•").foregroundStyle(.secondary)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level { case 1: 30; case 2: 25; case 3: 20; case 4: 17; default: 15 }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    static func safeImageURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }
}

private struct RemoteMarkdownImage: View {
    let alt: String
    let url: URL
    @State private var shouldLoad = false

    var body: some View {
        Group {
            if shouldLoad {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit()
                    case .failure: Label(alt.isEmpty ? "Image could not be loaded" : alt, systemImage: "photo.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                    default: ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 360)
            } else {
                Button {
                    shouldLoad = true
                } label: {
                    Label(alt.isEmpty ? "Load remote image" : "Load remote image: \(alt)", systemImage: "photo")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MarkdownEditorAction: Equatable {
    enum Kind: Equatable {
        case heading(Int), bold, italic, strike, code, link, quote, bullet, numbered, task, codeBlock, table, rule
    }
    let id = UUID()
    let kind: Kind

    static func == (left: Self, right: Self) -> Bool { left.id == right.id }
}

struct MarkdownSourceEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var action: MarkdownEditorAction? = nil
    var accessibilityLabel: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let editor = scrollView.documentView as? NSTextView else { return scrollView }
        editor.delegate = context.coordinator
        editor.string = text
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 5, height: 8)
        editor.font = .systemFont(ofSize: 15)
        editor.textColor = .labelColor
        editor.setAccessibilityLabel(accessibilityLabel)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        context.coordinator.editor = editor
        context.coordinator.highlight(editor)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scrollView.documentView as? NSTextView else { return }
        if editor.string != text {
            let selection = editor.selectedRange()
            editor.string = text
            editor.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
            context.coordinator.highlight(editor)
        }
        if let action, context.coordinator.lastActionID != action.id {
            context.coordinator.lastActionID = action.id
            let coordinator = context.coordinator
            // Publish edits after SwiftUI has finished updating the represented view.
            DispatchQueue.main.async { [weak editor] in
                guard let editor, editor.window != nil else { return }
                coordinator.apply(action.kind, to: editor)
                editor.window?.makeFirstResponder(editor)
            }
        }
        if isFocused, editor.window?.firstResponder !== editor {
            DispatchQueue.main.async { editor.window?.makeFirstResponder(editor) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownSourceEditor
        weak var editor: NSTextView?
        var lastActionID: UUID?

        init(_ parent: MarkdownSourceEditor) { self.parent = parent }

        func textDidBeginEditing(_ notification: Notification) { parent.isFocused = true }
        func textDidEndEditing(_ notification: Notification) { parent.isFocused = false }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
            highlight(editor)
        }

        func highlight(_ editor: NSTextView) {
            guard let layout = editor.layoutManager else { return }
            let source = editor.string as NSString
            let full = NSRange(location: 0, length: source.length)
            [.font, .foregroundColor, .backgroundColor, .underlineStyle, .strikethroughStyle].forEach {
                layout.removeTemporaryAttribute($0, forCharacterRange: full)
            }
            apply(#"(?m)^(#{1,6})[ \t]+.*$"#, source: source) { match in
                let marker = match.range(at: 1)
                let level = max(1, marker.length)
                layout.addTemporaryAttribute(.font, value: NSFont.systemFont(ofSize: self.headingSize(level), weight: .semibold), forCharacterRange: match.range)
                layout.addTemporaryAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, forCharacterRange: marker)
            }
            apply(#"(?m)^\s*>.*$"#, source: source) { match in
                layout.addTemporaryAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, forCharacterRange: match.range)
            }
            apply(#"(?m)^\s*(?:[-+*]|\d+[.)])\s+"#, source: source) { match in
                layout.addTemporaryAttribute(.foregroundColor, value: NSColor.controlAccentColor, forCharacterRange: match.range)
            }
            apply(#"\*\*.+?\*\*|__.+?__"#, source: source) { match in
                layout.addTemporaryAttribute(.font, value: NSFont.systemFont(ofSize: 15, weight: .semibold), forCharacterRange: match.range)
            }
            apply(#"~~.+?~~"#, source: source) { match in
                layout.addTemporaryAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: match.range)
            }
            apply(#"`[^`\n]+`"#, source: source) { match in
                layout.addTemporaryAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), forCharacterRange: match.range)
                layout.addTemporaryAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor.withAlphaComponent(0.18), forCharacterRange: match.range)
            }
            apply(#"\[[^\]]+\]\([^)]+\)"#, source: source) { match in
                layout.addTemporaryAttribute(.foregroundColor, value: NSColor.linkColor, forCharacterRange: match.range)
                layout.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: match.range)
            }
        }

        func apply(_ kind: MarkdownEditorAction.Kind, to editor: NSTextView) {
            switch kind {
            case .heading(let level): prefixLines(String(repeating: "#", count: level) + " ", replacingHeading: true, in: editor)
            case .bold: wrap("**", "**", in: editor)
            case .italic: wrap("_", "_", in: editor)
            case .strike: wrap("~~", "~~", in: editor)
            case .code: wrap("`", "`", in: editor)
            case .link: wrap("[", "](https://)", in: editor)
            case .quote: prefixLines("> ", in: editor)
            case .bullet: prefixLines("- ", in: editor)
            case .numbered: prefixLines("1. ", in: editor)
            case .task: prefixLines("- [ ] ", in: editor)
            case .codeBlock: wrap("```\n", "\n```", in: editor)
            case .table: insertBlock("| Column 1 | Column 2 |\n| --- | --- |\n| Value | Value |", in: editor)
            case .rule: insertBlock("---", in: editor)
            }
            parent.text = editor.string
            highlight(editor)
        }

        private func wrap(_ opening: String, _ closing: String, in editor: NSTextView) {
            let range = editor.selectedRange()
            let selected = (editor.string as NSString).substring(with: range)
            let replacement = opening + selected + closing
            editor.insertText(replacement, replacementRange: range)
            editor.setSelectedRange(NSRange(location: range.location + opening.utf16.count, length: selected.utf16.count))
        }

        private func prefixLines(_ prefix: String, replacingHeading: Bool = false, in editor: NSTextView) {
            let source = editor.string as NSString
            let selection = editor.selectedRange()
            let lineRange = source.lineRange(for: selection)
            let lines = source.substring(with: lineRange).components(separatedBy: "\n")
            let replacement = lines.enumerated().map { index, line -> String in
                if line.isEmpty, index == lines.count - 1, lines.count > 1 { return line }
                let content = replacingHeading ? line.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression) : line
                return prefix + content
            }.joined(separator: "\n")
            editor.insertText(replacement, replacementRange: lineRange)
            editor.setSelectedRange(NSRange(location: lineRange.location, length: replacement.utf16.count))
        }

        private func insertBlock(_ block: String, in editor: NSTextView) {
            let range = editor.selectedRange()
            let before = range.location > 0 && !(editor.string as NSString).substring(with: NSRange(location: range.location - 1, length: 1)).contains("\n") ? "\n" : ""
            let replacement = before + block + "\n"
            editor.insertText(replacement, replacementRange: range)
            editor.setSelectedRange(NSRange(location: range.location + replacement.utf16.count, length: 0))
        }

        private func apply(_ pattern: String, source: NSString, body: (NSTextCheckingResult) -> Void) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            regex.matches(in: source as String, range: NSRange(location: 0, length: source.length)).forEach(body)
        }

        private func headingSize(_ level: Int) -> CGFloat {
            switch level { case 1: 28; case 2: 24; case 3: 20; case 4: 18; default: 16 }
        }
    }
}

struct MarkdownToolbar: View {
    let perform: (MarkdownEditorAction.Kind) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                menu
                tool("bold", "Bold", .bold)
                tool("italic", "Italic", .italic)
                tool("strikethrough", "Strikethrough", .strike)
                tool("chevron.left.forwardslash.chevron.right", "Inline code", .code)
                tool("link", "Link", .link)
                Divider().frame(height: 18).padding(.horizontal, 4)
                tool("list.bullet", "Bulleted list", .bullet)
                tool("list.number", "Numbered list", .numbered)
                tool("checklist", "Checklist", .task)
                tool("text.quote", "Quote", .quote)
                tool("curlybraces", "Code block", .codeBlock)
                tool("tablecells", "Table", .table)
                tool("minus", "Divider", .rule)
            }
        }
    }

    private var menu: some View {
        Menu {
            ForEach(1...6, id: \.self) { level in Button("Heading \(level)") { perform(.heading(level)) } }
        } label: {
            Label("Heading", systemImage: "textformat.size").font(.system(size: 11, weight: .medium)).padding(.horizontal, 9).frame(height: 28)
        }
        .menuStyle(.borderlessButton).fixedSize().help("Heading")
    }

    private func tool(_ icon: String, _ help: String, _ action: MarkdownEditorAction.Kind) -> some View {
        Button { perform(action) } label: { Image(systemName: icon).frame(width: 28, height: 28) }
            .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
}
