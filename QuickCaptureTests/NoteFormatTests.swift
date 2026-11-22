import UIKit
import Testing
@testable import QuickCapture

struct NoteFormatTests {
    @Test func passageBecomesQuoteWithNoteUnderIt() {
        #expect(NoteFormat.snap(passage: "First line\nsecond line", note: " My thought ") ==
                "> First line\n>\n> second line\n\nMy thought")
    }

    @Test func paragraphsStayInOneQuote() {
        #expect(NoteFormat.quote("One.\n\n\nTwo.\n\n") == "> One.\n>\n> Two.")
    }

    @Test func noNoteMeansJustTheQuote() {
        #expect(NoteFormat.snap(passage: "Text", note: "  ") == "> Text")
    }

    @Test func findsQuoteLinesAndTheirMarkers() {
        let ranges = NoteFormat.lineRanges(in: "> Quoted\n>\nMy note")
        #expect(ranges.map(\.isQuote) == [true, true, false])
        #expect(ranges.map(\.markerLength) == [2, 1, 0])
        #expect(ranges[2].range == NSRange(location: 11, length: 7))
    }

    @Test func unquotedDropsTheMarker() {
        #expect(NoteFormat.unquoted("> Text") == "Text")
        #expect(NoteFormat.unquoted(">") == "")
        #expect(NoteFormat.unquoted("Plain") == "Plain")
    }
}

struct MarkdownFormatterTests {
    private let date = Date(timeIntervalSince1970: 1_795_000_000) // 2026-11-18 11:06:40 UTC
    private let singapore = TimeZone(identifier: "Asia/Singapore")!

    @Test func noteHasArticleSaverFrontMatterThenThePage() {
        let note = MarkdownFormatter.note(page: "> A passage\n\nMy note\n", title: "The \"Two\" Towers",
                                          at: date, in: singapore)
        #expect(note.text == """
            ---
            source: quick-capture
            captured_at: 2026-11-18T19:06:40+08:00
            status: fleeting
            title: "The \\"Two\\" Towers"
            tags:
              - "reading"
            ---

            # The "Two" Towers

            > A passage

            My note

            """)
        #expect(note.fileName == "2026-11-18-190640-the-two-towers.md")
    }

    @Test func blankTitleFallsBackToReadingNotes() {
        let note = MarkdownFormatter.note(page: "Text", title: "  ", at: date, in: singapore)
        #expect(note.text.contains("title: \"Reading notes\""))
        #expect(note.fileName == "2026-11-18-190640-reading-notes.md")
    }
}

struct RichTextFormatterTests {
    @Test func quotesLoseTheirMarkersAndAreItalic() {
        let note = RichTextFormatter.note(page: "> A passage\n\nMy note", title: "Book")
        #expect(note.string == "Book\nA passage\n\nMy note")

        let quoteFont = note.attribute(.font, at: (note.string as NSString).range(of: "A passage").location,
                                       effectiveRange: nil) as? UIFont
        let noteFont = note.attribute(.font, at: (note.string as NSString).range(of: "My note").location,
                                      effectiveRange: nil) as? UIFont
        #expect(quoteFont?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
        #expect(noteFont?.fontDescriptor.symbolicTraits.contains(.traitItalic) == false)
    }
}
