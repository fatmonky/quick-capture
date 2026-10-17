import CoreGraphics
import Foundation

/// Rebuilds flowing text from OCR lines. Kept free of UIKit/Vision so the
/// logic can be unit tested with synthetic line positions.
enum TextLayout {
    /// One recognized line of text. `box` is normalized (0–1) with the origin at
    /// the bottom-left of the image, as Vision reports it.
    struct Line: Equatable {
        var text: String
        var box: CGRect
    }

    /// The lines whose centre lies inside `region`, given as a fraction of the
    /// image with the origin at the top-left (as on screen, unlike Vision).
    static func lines(_ lines: [Line], centredIn region: CGRect) -> [Line] {
        lines.filter { region.contains(CGPoint(x: $0.box.midX, y: 1 - $0.box.midY)) }
    }

    /// Turns OCR lines (in Vision's reading order) back into paragraphs:
    /// - fragments from outside the main text column (e.g. the edge of a facing
    ///   page) are dropped;
    /// - pieces Vision split from the same printed line are put back together;
    /// - lines that wrap within a paragraph are joined with a space, re-joining
    ///   words hyphenated across the line break;
    /// - a line that stops short of the right margin, or a following line that is
    ///   indented, ends the paragraph with a line break;
    /// - an unusually large gap, or a jump back up the page, becomes a blank line.
    ///
    /// Spacing is judged from line *centres*, since on a tilted or curved page
    /// neighbouring line boxes often overlap.
    static func assemble(_ rawLines: [Line]) -> String {
        let cleaned = rawLines
            .map { Line(text: $0.text.trimmingCharacters(in: .whitespaces), box: $0.box) }
            .filter { !$0.text.isEmpty }
        guard !cleaned.isEmpty else { return "" }

        let column = Column(of: cleaned)
        let rows = mergeSplitRows(cleaned.filter { !column.isStrayFragment($0) })
        guard let first = rows.first else { return "" }

        let lineHeight = median(rows.map(\.box.height))
        let steps = zip(rows, rows.dropFirst())
            .map { $0.box.midY - $1.box.midY }
            .filter { $0 > lineHeight * 0.3 }
        // Normal line spacing is close to the line height; the cap stops a page
        // with only a few, widely spaced lines from treating big gaps as normal.
        let lineStep = min(steps.isEmpty ? lineHeight * 1.2 : median(steps), lineHeight * 1.4)

        var result = first.text
        for (previous, line) in zip(rows, rows.dropFirst()) {
            let step = previous.box.midY - line.box.midY
            let endedShort = previous.box.maxX < column.right - column.width * 0.12
            let indented = line.box.minX - previous.box.minX > lineHeight * 0.6

            if step < lineHeight * 0.3 || step > lineStep * 1.6 {
                result += "\n\n" + line.text
            } else if endedShort || indented {
                result += "\n" + line.text
            } else {
                result = joinWrapped(result, line.text)
            }
        }
        return result
    }

    /// The horizontal extent of the main body of text.
    private struct Column {
        var left: CGFloat
        var right: CGFloat
        var width: CGFloat { right - left }

        init(of lines: [Line]) {
            let widest = lines.map(\.box.width).max() ?? 0
            let bodyLines = lines.filter { $0.box.width >= widest * 0.5 }
            left = TextLayout.median(bodyLines.map(\.box.minX))
            right = TextLayout.median(bodyLines.map(\.box.maxX))
        }

        /// A short fragment whose centre lies outside the column, like words
        /// cut off at the edge of the opposite page.
        func isStrayFragment(_ line: Line) -> Bool {
            line.box.width < width * 0.3 && (line.box.midX < left || line.box.midX > right)
        }
    }

    /// Merges consecutive pieces that sit side by side on the same printed line.
    private static func mergeSplitRows(_ lines: [Line]) -> [Line] {
        var rows: [Line] = []
        for line in lines {
            if let last = rows.last, isSameRow(last, line) {
                let (leftPiece, rightPiece) = last.box.minX <= line.box.minX ? (last, line) : (line, last)
                rows[rows.count - 1] = Line(text: leftPiece.text + " " + rightPiece.text,
                                            box: last.box.union(line.box))
            } else {
                rows.append(line)
            }
        }
        return rows
    }

    private static func isSameRow(_ a: Line, _ b: Line) -> Bool {
        let verticalOverlap = min(a.box.maxY, b.box.maxY) - max(a.box.minY, b.box.minY)
        let horizontalOverlap = min(a.box.maxX, b.box.maxX) - max(a.box.minX, b.box.minX)
        return verticalOverlap > min(a.box.height, b.box.height) * 0.5
            && horizontalOverlap < min(a.box.width, b.box.width) * 0.2
    }

    private static func joinWrapped(_ text: String, _ next: String) -> String {
        let beforeHyphen = text.dropLast().last
        if text.hasSuffix("-"), beforeHyphen?.isLetter == true, next.first?.isLowercase == true {
            return text.dropLast() + next
        }
        return text + " " + next
    }

    fileprivate static func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        return values.sorted()[values.count / 2]
    }
}
