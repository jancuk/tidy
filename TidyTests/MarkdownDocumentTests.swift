import Testing
@testable import Tidy

struct MarkdownDocumentTests {
    @Test func parsesCommonBlockSyntax() {
        let source = """
        ### A heading

        **Bold** and [a link](https://example.com)

        > A quote

        - [x] Finished
          - Nested
        3. Numbered

        ```swift
        let value = true
        ```

        | Name | Value |
        | --- | ---: |
        | One | 1 |

        ![Preview](https://example.com/image.png)

        ---
        """
        let blocks = MarkdownDocument.parse(source)

        #expect(blocks[0] == .heading(level: 3, text: "A heading"))
        #expect(blocks.contains(.quote("A quote")))
        #expect(blocks.contains(.code(language: "swift", content: "let value = true")))
        #expect(blocks.contains(.table(headings: ["Name", "Value"], rows: [["One", "1"]])))
        #expect(blocks.contains(.image(alt: "Preview", url: "https://example.com/image.png")))
        #expect(MarkdownDocumentView.safeImageURL("https://example.com/image.png") != nil)
        #expect(MarkdownDocumentView.safeImageURL("http://example.com/image.png") == nil)
        #expect(MarkdownDocumentView.safeImageURL("https://user:secret@example.com/image.png") == nil)
        #expect(blocks.last == .rule)

        let list = blocks.compactMap { block -> [MarkdownListItem]? in
            if case .list(let items) = block { return items }
            return nil
        }.first
        #expect(list?.first?.checked == true)
        #expect(list?[1].depth == 1)
        #expect(list?[2].number == 3)
    }

    @Test func markdownNotesKeepPortableSourceAndDerivePlainTitles() {
        let source = "### **Release notes**\n\n- Added previews"
        var item = ProductivityItem(kind: .note)
        item.setMarkdownSource(source)

        #expect(item.contentFormat == .markdown)
        #expect(item.markdownSource == source)
        #expect(item.body == source)
        #expect(item.title == "Release notes")
    }

    @Test func legacyNotesBecomeOneMarkdownDocumentWithoutDuplication() {
        let oldSplitNote = ProductivityItem(kind: .note, title: "Title", body: "Body")
        let oldCapturedNote = ProductivityItem(kind: .note, title: "Title", body: "Title\nBody")

        #expect(oldSplitNote.markdownSource == "Title\nBody")
        #expect(oldCapturedNote.markdownSource == "Title\nBody")
    }
}
