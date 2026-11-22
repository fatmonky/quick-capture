import Foundation
import Testing
@testable import QuickCapture

struct HighlightsTests {
    private func range(of part: String, in text: String) -> NSRange { (text as NSString).range(of: part) }

    @Test func parsesHighlightsOutOfALine() {
        let line = Highlights.parse("> Some ==bright== words and ==more==")
        #expect(line.prefix == "> ")
        #expect(line.content == "Some bright words and more")
        #expect(line.highlights.map { line.text(of: $0) } == ["bright", "more"])
        #expect(line.serialized == "> Some ==bright== words and ==more==")
    }

    @Test func unclosedMarkersAreJustText() {
        #expect(Highlights.parse("a == b").content == "a == b")
        #expect(Highlights.parse("a == b").highlights.isEmpty)
    }

    @Test func highlightsTheSelectionWithoutSpacesOrQuoteMarkers() throws {
        let text = "> One two three\n>\n> Four five"
        let edit = try #require(Highlights.highlight(text, selection: range(of: " two three\n>\n> Four", in: text)))
        #expect(edit.text == "> One ==two three==\n>\n> ==Four== five")
        #expect(edit.cursor == (edit.text as NSString).range(of: "> ==Four== five").upperBound)
    }

    @Test func overlappingHighlightsJoin() throws {
        let text = "> One ==two== three"
        let edit = try #require(Highlights.highlight(text, selection: range(of: "two== thr", in: text)))
        #expect(edit.text == "> One ==two thr==ee")
    }

    @Test func blankSelectionHighlightsNothing() {
        #expect(Highlights.highlight("a   b", selection: NSRange(location: 1, length: 3)) == nil)
    }

    @Test func cursorOnAHighlightFindsAndRemovesIt() throws {
        let text = "> One ==two== three ==four=="
        let cursor = NSRange(location: range(of: "two", in: text).location + 1, length: 0)
        #expect(Highlights.isHighlighted(text, selection: cursor))
        #expect(!Highlights.isHighlighted(text, selection: NSRange(location: 2, length: 0)))
        #expect(try #require(Highlights.removeHighlights(text, selection: cursor)).text == "> One two three ==four==")
    }

    @Test func noteGoesUnderTheParagraphBetweenQuoteParagraphs() {
        let text = "> ==One==\n>\n> Two"
        let edit = Highlights.addNote(text, at: 3)
        #expect(edit.text == "> ==One==\n\n\n\n> Two")
        #expect(edit.cursor == ("> ==One==\n\n" as NSString).length)
    }

    @Test func noteGoesAfterNotesAlreadyThere() {
        let text = "> ==One==\n\nFirst note\n\n> Two"
        let edit = Highlights.addNote(text, at: 3)
        #expect(edit.text == "> ==One==\n\nFirst note\n\n\n\n> Two")
        #expect(edit.cursor == ("> ==One==\n\nFirst note\n\n" as NSString).length)
    }

    @Test func noteAtTheEndOfThePage() {
        let edit = Highlights.addNote("> ==One==", at: 3)
        #expect(edit.text == "> ==One==\n\n")
        #expect(edit.cursor == 11)
    }

    @Test func highlightRunningOverParagraphsIsOnePassage() {
        let page = "> Start ==of one==\n>\n> ==and its end== then\n>\n> ==another==\n\nA note ==too=="
        #expect(Highlights.passages(in: page) == [["of one", "and its end"], ["another"], ["too"]])
    }
}

struct WhatsAppFormatterTests {
    @Test func highlightsAreBoldAndSeparated() {
        let page = "> Start ==of one==\n>\n> ==and its end== then\n>\n> ==another==\n\nMy note"
        let message = WhatsAppFormatter.message(page: page, title: "Adaptation under Fire")
        #expect(message.text == "*Adaptation under Fire*\n\n*of one*\n\n*and its end*\n\n…\n\n*another*")
        #expect(message.highlightCount == 2)
        #expect(!message.isTruncated)
    }

    @Test func withoutHighlightsThePassagesGoPlain() {
        let message = WhatsAppFormatter.message(page: "> One\n>\n> Two\n\nMy note\n\n> Three", title: "")
        #expect(message.text == "*Reading notes*\n\nOne\n\nTwo\n\n…\n\nThree")
        #expect(message.highlightCount == 0)
    }

    @Test func longMessageIsCutShort() {
        let page = "> ==\(String(repeating: "word ", count: 13_000))=="
        let message = WhatsAppFormatter.message(page: page, title: "Long")
        #expect(message.isTruncated)
        #expect(message.text.count <= WhatsAppFormatter.maxLength)
        #expect(message.text.hasSuffix(WhatsAppFormatter.truncationNote))
    }
}
