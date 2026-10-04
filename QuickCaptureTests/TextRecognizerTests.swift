import Testing
import UIKit
@testable import QuickCapture

struct TextRecognizerAssembleTests {
    /// Builds a line in Vision coordinates: `row` 0 is the top line, each row is
    /// 0.05 tall with `spacing` between rows; `width` is the fraction of the full line.
    private func line(_ text: String, row: Double, width: Double = 0.8,
                      spacing: Double = 0.01, top: Double = 0.9) -> TextRecognizer.Line {
        let height = 0.05
        let maxY = top - row * (height + spacing)
        return .init(text: text, box: CGRect(x: 0.1, y: maxY - height, width: width, height: height))
    }

    @Test func emptyInputGivesEmptyString() {
        #expect(TextRecognizer.assemble([]) == "")
    }

    @Test func wrappedLinesJoinWithSpaces() {
        let lines = [
            line("The quick brown fox", row: 0),
            line("jumps over the lazy", row: 1),
            line("dog.", row: 2, width: 0.1),
        ]
        #expect(TextRecognizer.assemble(lines) == "The quick brown fox jumps over the lazy dog.")
    }

    @Test func hyphenatedWordIsRejoined() {
        let lines = [
            line("an extraordi-", row: 0),
            line("nary example", row: 1),
        ]
        #expect(TextRecognizer.assemble(lines) == "an extraordinary example")
    }

    @Test func hyphenBeforeCapitalIsKept() {
        let lines = [
            line("the pre-", row: 0),
            line("Raphaelite painters", row: 1),
        ]
        #expect(TextRecognizer.assemble(lines) == "the pre- Raphaelite painters")
    }

    @Test func shortLineEndsWithLineBreak() {
        let lines = [
            line("Chapter One", row: 0, width: 0.3),
            line("It was a bright cold day in April, and", row: 1),
            line("the clocks were striking thirteen.", row: 2),
        ]
        #expect(TextRecognizer.assemble(lines) ==
                "Chapter One\nIt was a bright cold day in April, and the clocks were striking thirteen.")
    }

    @Test func largeGapBecomesBlankLine() {
        let lines = [
            line("First paragraph ends here.", row: 0),
            line("Second paragraph starts here.", row: 2),
        ]
        #expect(TextRecognizer.assemble(lines) == "First paragraph ends here.\n\nSecond paragraph starts here.")
    }

    @Test func whitespaceOnlyLinesAreDropped() {
        let lines = [line("  Hello  ", row: 0), line("   ", row: 1)]
        #expect(TextRecognizer.assemble(lines) == "Hello")
    }
}

/// Runs real Vision OCR on an image rendered in the test.
struct TextRecognizerOCRTests {
    private func renderPage(_ lines: [String]) -> UIImage {
        let size = CGSize(width: 1200, height: 800)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 56),
                .foregroundColor: UIColor.black,
            ]
            for (index, text) in lines.enumerated() {
                (text as NSString).draw(at: CGPoint(x: 60, y: 80 + index * 100), withAttributes: attributes)
            }
        }
    }

    @Test func recognizesRenderedText() async throws {
        let image = renderPage(["Quick Capture reads", "printed text aloud"])
        let text = try await TextRecognizer.recognize([image])
        #expect(text.contains("Quick Capture"))
        #expect(text.contains("printed text"))
    }

    @Test func multiplePagesAreSeparatedByBlankLine() async throws {
        let text = try await TextRecognizer.recognize([
            renderPage(["Page one"]),
            renderPage(["Page two"]),
        ])
        #expect(text == "Page one\n\nPage two")
    }
}
