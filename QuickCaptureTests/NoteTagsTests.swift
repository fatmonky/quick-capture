import Foundation
import PDFKit
import Testing
@testable import QuickCapture

struct NoteTagsTests {
    @Test func parsesTypedTags() {
        #expect(NoteTags.parse("#Strategy, power #strategy #system_of-record") == ["strategy", "power", "system_of-record"])
        #expect(NoteTags.display(["strategy", "power"]) == "#strategy #power")
    }

    @Test func suggestsTagsMatchingWhatsBeingTyped() {
        let used = ["power", "strategy", "system_of_record"]
        #expect(NoteTags.suggestions(for: "#power #s", from: used) == ["strategy", "system_of_record"])
        #expect(NoteTags.suggestions(for: "#rec", from: used) == ["system_of_record"])
        #expect(NoteTags.suggestions(for: "#power ", from: used) == used)
        #expect(NoteTags.completing("#power #str", with: "strategy") == "#power #strategy #")
    }

    @Test func remembersTagsMostUsedFirst() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoteTagsTests-\(UUID())"))
        NoteTags.remember(["power", "strategy"], in: defaults)
        NoteTags.remember(["strategy"], in: defaults)
        #expect(NoteTags.used(in: defaults) == ["strategy", "power"])
    }

    @MainActor @Test func storeKeepsTagsAndClearTakesThemOff() throws {
        let url = URL.temporaryDirectory.appending(path: "tags-\(UUID()).txt")
        let store = CaptureStore(fileURL: url)
        store.tags = ["strategy", "power"]
        #expect(CaptureStore(fileURL: url).tags == ["strategy", "power"])
        store.clear()
        #expect(CaptureStore(fileURL: url).tags.isEmpty)
    }

    @Test func markdownFrontMatterHasTheTagsAfterReading() {
        let note = MarkdownFormatter.note(page: "Text", title: "Book", tags: ["strategy", "reading", "power"])
        #expect(note.text.contains("tags:\n  - \"reading\"\n  - \"strategy\"\n  - \"power\"\n---"))
    }

    @Test func pdfAndNotesShowTheTags() throws {
        let pdf = try #require(PDFDocument(data: PDFExporter.pdfData(page: "Text", title: "Book", tags: ["strategy", "power"])))
        #expect(pdf.string?.contains("#strategy #power") == true)
        #expect(RichTextFormatter.note(page: "Text", title: "Book", tags: ["strategy"]).string == "Book\n#strategy\n\nText")
    }
}
