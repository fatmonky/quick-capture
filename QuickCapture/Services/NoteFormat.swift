import Foundation
import UIKit

/// The page is written in Markdown: snapped passages are quotes (`> …`), and
/// everything else (notes, typed or spoken) is plain text in your own words.
enum NoteFormat {
    /// A snapped passage as a Markdown quote, followed by a note on it, if any.
    static func snap(passage: String, note: String = "") -> String {
        let quote = self.quote(passage)
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return [quote, note].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// Every paragraph of `passage` (each line, as Snap lays text out) starts with
    /// `> `, with a `>` line between paragraphs so Markdown keeps them apart within
    /// one quote.
    static func quote(_ passage: String) -> String {
        passage.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { "> " + $0 }
            .joined(separator: "\n>\n")
    }

    /// Whether a line of the page belongs to a quote.
    static func isQuote<S: StringProtocol>(_ line: S) -> Bool {
        line.drop(while: { $0 == " " }).first == ">"
    }

    /// A quote line without its `>` marker.
    static func unquoted<S: StringProtocol>(_ line: S) -> String {
        var text = line.drop(while: { $0 == " " })
        if text.first == ">" { text = text.dropFirst() }
        if text.first == " " { text = text.dropFirst() }
        return String(text)
    }

    /// One line of the page, with where it sits in the text (in UTF-16, as UIKit counts).
    struct LineRange: Equatable {
        var range: NSRange
        var isQuote: Bool
        /// The length of the `> ` marker at the start of a quote line.
        var markerLength: Int
    }

    static func lineRanges(in text: String) -> [LineRange] {
        let string = text as NSString
        var result: [LineRange] = []
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length),
                                   options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            let line = string.substring(with: range)
            let isQuote = isQuote(line)
            let marker = isQuote ? (line as NSString).length - (unquoted(line) as NSString).length : 0
            result.append(LineRange(range: range, isQuote: isQuote, markerLength: marker))
        }
        return result
    }
}

/// A Markdown note, ready to be saved or shared.
struct MarkdownNote: Equatable {
    var fileName: String
    var text: String
}

/// Formats the page as a note for Obsidian, in the same shape as Article Saver's notes:
///
/// ```
/// ---
/// source: quick-capture
/// captured_at: 2026-11-22T10:15:30+08:00
/// status: fleeting
/// title: "The Lord of the Rings"
/// tags:
///   - "reading"
///   - "strategy"
/// ---
///
/// # The Lord of the Rings
///
/// > A passage from the book.
///
/// My note on it.
/// ```
enum MarkdownFormatter {
    static let defaultTitle = "Reading notes"
    static let maxSlugLength = 60

    static func note(page: String, title: String, tags: [String] = [], at date: Date = .now,
                     in timeZone: TimeZone = .current) -> MarkdownNote {
        let title = collapse(title).isEmpty ? defaultTitle : collapse(title)
        let timestamp = ISO8601DateFormatter()
        timestamp.timeZone = timeZone
        let frontMatter = [
            "---",
            "source: quick-capture",
            "captured_at: \(timestamp.string(from: date))",
            "status: fleeting",
            "title: \(quoted(title))",
            "tags:",
        ] + (["reading"] + tags.filter { $0 != "reading" }).map { "  - \(quoted($0))" } + [
            "---",
        ]
        let frontMatterText = frontMatter.joined(separator: "\n")
        let body = page.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = [frontMatterText, "# \(title)", body].filter { !$0.isEmpty }.joined(separator: "\n\n") + "\n"
        return MarkdownNote(fileName: fileName(title: title, stamp: stamp(date, in: timeZone)), text: text)
    }

    static func stamp(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }

    /// `2026-11-22-101530-the-lord-of-the-rings.md`. The time keeps a later export
    /// from replacing a note edited since.
    static func fileName(title: String, stamp: String) -> String {
        let words = title.lowercased().split { !$0.isLetter && !$0.isNumber }
        var slug = ""
        for word in words where slug.count + word.count < maxSlugLength {
            slug += (slug.isEmpty ? "" : "-") + word
        }
        return [stamp, slug].filter { !$0.isEmpty }.joined(separator: "-") + ".md"
    }

    static func quoted(_ value: String) -> String {
        let escaped = value.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// Formats the page as rich text for Apple Notes, which doesn't read Markdown:
/// quotes are indented and in italics, highlights are marked, and notes are plain.
enum RichTextFormatter {
    static func note(page: String, title: String, tags: [String] = []) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let title = MarkdownFormatter.collapse(title)
        if !title.isEmpty {
            result.append(NSAttributedString(string: title + "\n", attributes: [
                .font: UIFont.preferredFont(forTextStyle: .title2).withTraits(.traitBold),
            ]))
        }
        if !tags.isEmpty {
            result.append(NSAttributedString(string: NoteTags.display(tags) + "\n\n", attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline), .foregroundColor: UIColor.secondaryLabel,
            ]))
        }

        let body = UIFont.preferredFont(forTextStyle: .body)
        let quoteStyle = NSMutableParagraphStyle()
        quoteStyle.firstLineHeadIndent = 20
        quoteStyle.headIndent = 20
        let lines = page.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            let ending = index == lines.count - 1 ? "" : "\n"
            let parsed = Highlights.parse(line)
            let attributes: [NSAttributedString.Key: Any] = NoteFormat.isQuote(line)
                ? [.font: body.withTraits(.traitItalic), .paragraphStyle: quoteStyle]
                : [.font: body]
            result.append(Highlights.attributed(parsed, attributes: attributes, highlight: PDFExporter.highlight))
            result.append(NSAttributedString(string: ending, attributes: attributes))
        }
        return result
    }
}

extension Highlights {
    /// A line's text, without markers, with `highlight` added to the highlighted parts.
    static func attributed(_ line: Line, attributes: [NSAttributedString.Key: Any],
                           highlight: UIColor) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: line.content, attributes: attributes)
        for range in line.highlights {
            result.addAttribute(.backgroundColor, value: highlight,
                                range: NSRange(location: range.lowerBound, length: range.count))
        }
        return result
    }
}

extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits)) else {
            return self
        }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
