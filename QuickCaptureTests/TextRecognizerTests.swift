import Testing
import UIKit
@testable import QuickCapture

struct TextLayoutTests {
    /// Builds a line in Vision coordinates: `row` 0 is the top line, each row is
    /// 0.05 tall with `spacing` between rows; `width` is the fraction of the full line.
    private func line(_ text: String, row: Double, width: Double = 0.8,
                      spacing: Double = 0.01, top: Double = 0.9) -> TextLayout.Line {
        let height = 0.05
        let maxY = top - row * (height + spacing)
        return .init(text: text, box: CGRect(x: 0.1, y: maxY - height, width: width, height: height))
    }

    @Test func emptyInputGivesEmptyString() {
        #expect(TextLayout.assemble([]) == "")
    }

    @Test func wrappedLinesJoinWithSpaces() {
        let lines = [
            line("The quick brown fox", row: 0),
            line("jumps over the lazy", row: 1),
            line("dog.", row: 2, width: 0.1),
        ]
        #expect(TextLayout.assemble(lines) == "The quick brown fox jumps over the lazy dog.")
    }

    @Test func hyphenatedWordIsRejoined() {
        let lines = [
            line("an extraordi-", row: 0),
            line("nary example", row: 1),
        ]
        #expect(TextLayout.assemble(lines) == "an extraordinary example")
    }

    @Test func hyphenBeforeCapitalIsKept() {
        let lines = [
            line("the pre-", row: 0),
            line("Raphaelite painters", row: 1),
        ]
        #expect(TextLayout.assemble(lines) == "the pre- Raphaelite painters")
    }

    @Test func shortLineEndsWithLineBreak() {
        let lines = [
            line("Chapter One", row: 0, width: 0.3),
            line("It was a bright cold day in April, and", row: 1),
            line("the clocks were striking thirteen.", row: 2),
        ]
        #expect(TextLayout.assemble(lines) ==
                "Chapter One\nIt was a bright cold day in April, and the clocks were striking thirteen.")
    }

    @Test func largeGapBecomesBlankLine() {
        let lines = [
            line("First paragraph ends here.", row: 0),
            line("Second paragraph starts here.", row: 2),
        ]
        #expect(TextLayout.assemble(lines) == "First paragraph ends here.\n\nSecond paragraph starts here.")
    }

    @Test func overlappingBoxesOnTiltedPageStillJoin() {
        // Boxes taller than the line spacing, as on a tilted or curved page.
        let lines = [
            TextLayout.Line(text: "temporarily relocating personnel, tem-", box: CGRect(x: 0.1, y: 0.86, width: 0.74, height: 0.034)),
            TextLayout.Line(text: "porarily reassigning duties, and", box: CGRect(x: 0.1, y: 0.833, width: 0.74, height: 0.037)),
            TextLayout.Line(text: "expanding responsibilities.", box: CGRect(x: 0.1, y: 0.810, width: 0.74, height: 0.031)),
        ]
        #expect(TextLayout.assemble(lines) ==
                "temporarily relocating personnel, temporarily reassigning duties, and expanding responsibilities.")
    }

    @Test func fragmentsFromFacingPageAreDropped() {
        let lines = [
            TextLayout.Line(text: "t realit", box: CGRect(x: -0.01, y: 0.82, width: 0.08, height: 0.05)),
            TextLayout.Line(text: "consen-", box: CGRect(x: 0.0, y: 0.79, width: 0.07, height: 0.04)),
            line("The main column of text starts", row: 0),
            line("here and carries on.", row: 1),
        ]
        #expect(TextLayout.assemble(lines) == "The main column of text starts here and carries on.")
    }

    @Test func pieceSplitFromSameLineIsRejoined() {
        let row0 = line("ing responsibilities. It will disrupt", row: 0)
        var left = line("organization.", row: 1, width: 0.2)
        var right = line("This disruption is a driver", row: 1, width: 0.55)
        left.box.origin.x = 0.1
        right.box.origin.x = 0.35
        let row2 = line("of the transformation.", row: 2)
        #expect(TextLayout.assemble([row0, left, right, row2]) ==
                "ing responsibilities. It will disrupt organization. This disruption is a driver of the transformation.")
    }

    @Test func indentedLineStartsNewParagraph() {
        var indented = line("Second paragraph starts with an indent", row: 1)
        indented.box.origin.x += 0.05
        let lines = [
            line("First paragraph runs right to the margin", row: 0),
            indented,
            line("and continues here.", row: 2),
        ]
        #expect(TextLayout.assemble(lines) ==
                "First paragraph runs right to the margin\nSecond paragraph starts with an indent and continues here.")
    }

    @Test func whitespaceOnlyLinesAreDropped() {
        let lines = [line("  Hello  ", row: 0), line("   ", row: 1)]
        #expect(TextLayout.assemble(lines) == "Hello")
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

struct CaptureRegionTests {
    @Test func linesOutsideRegionAreDropped() {
        // Vision boxes have a bottom-left origin; the region has a top-left origin.
        let title = TextLayout.Line(text: "Title", box: CGRect(x: 0.3, y: 0.85, width: 0.4, height: 0.05))
        let body = TextLayout.Line(text: "Body", box: CGRect(x: 0.1, y: 0.5, width: 0.8, height: 0.05))
        let topBand = CGRect(x: 0.2, y: 0.05, width: 0.6, height: 0.15)
        #expect(TextLayout.lines([title, body], centredIn: topBand) == [title])
    }

    @Test func viewRectMapsToCroppedImage() {
        // A 3:4 portrait photo filling a taller 1:2 view: a sixth is cropped off each side.
        let region = LiveTextScannerController.region(
            of: CGRect(x: 0, y: 0, width: 100, height: 200),
            inViewSized: CGSize(width: 100, height: 200),
            aspectFilling: CGSize(width: 300, height: 400)
        )
        #expect(abs(region.minX - 1.0 / 6) < 0.001)
        #expect(abs(region.width - 2.0 / 3) < 0.001)
        #expect(region.minY == 0)
        #expect(region.height == 1)
    }
}
