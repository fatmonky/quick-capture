import PDFKit
import Testing
import UIKit
@testable import QuickCapture

struct PDFExporterTests {
    @Test func passagesGetTheNotesThatFollowThem() {
        let page = "Thoughts before reading\n\n> First passage\n>\n> its second paragraph\n\nMy note\n\nMore on it\n\n> Second passage\n\n> Third passage\n\nOn the third"
        #expect(PDFExporter.blocks(of: page) == [
            .text("Thoughts before reading"),
            .passage("First passage\nits second paragraph", note: 1),
            .note(1, "My note\n\nMore on it"),
            .passage("Second passage", note: nil),
            .passage("Third passage", note: 2),
            .note(2, "On the third"),
        ])
    }

    @Test func onlyHighlightsAreMarkedAndTheNoteNumberFollowsThem() {
        let text = PDFExporter.attributedText(page: "> A passage with ==a bright part== in it\n\nMy note", title: "Book", date: .now)
        let string = text.string as NSString
        func background(_ part: String) -> UIColor? {
            text.attribute(.backgroundColor, at: string.range(of: part).location, effectiveRange: nil) as? UIColor
        }
        #expect(background("A passage") == nil)
        #expect(background("bright part") == PDFExporter.highlight)
        #expect(background(" in it") == nil)
        #expect(string.contains("a bright part\u{2009}1 in it"))
        #expect(!string.contains("=="))
    }

    @Test func pageWithoutPassagesIsPlainText() {
        #expect(PDFExporter.blocks(of: "Just a thought\non two lines") == [.text("Just a thought\non two lines")])
    }

    @Test func pdfHasTitlePassagesAndNumberedNotes() throws {
        let data = PDFExporter.pdfData(page: "> A passage from the book\n\nMy note on it", title: "The Two Towers")
        let document = try #require(PDFDocument(data: data))
        let text = try #require(document.string)
        #expect(document.pageCount == 1)
        #expect(text.contains("The Two Towers"))
        #expect(text.contains("A passage from the book"))
        #expect(text.contains("Note 1"))
        #expect(text.contains("My note on it"))
        #expect(text.contains("1 / 1"))
        #expect(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "The Two Towers")
        #expect(document.page(at: 0)?.bounds(for: .mediaBox).size == PDFExporter.pageSize)
    }

    @Test func longPageRunsOntoMorePages() throws {
        let page = (1...80).map { "> Passage number \($0), long enough to wrap onto a second line of the page.\n\nA note on passage \($0)." }
            .joined(separator: "\n\n")
        let document = try #require(PDFDocument(data: PDFExporter.pdfData(page: page, title: "Long")))
        #expect(document.pageCount > 2)
        let last = try #require(document.page(at: document.pageCount - 1)?.string)
        #expect(last.contains("A note on passage 80."))
        #expect(last.contains("\(document.pageCount) / \(document.pageCount)"))
    }

    @Test func fileNameComesFromTheTitle() {
        #expect(PDFExporter.fileName(for: "The Two Towers: Book 3") == "The Two Towers  Book 3.pdf")
        #expect(PDFExporter.fileName(for: "  ") == "Reading notes.pdf")
    }
}
