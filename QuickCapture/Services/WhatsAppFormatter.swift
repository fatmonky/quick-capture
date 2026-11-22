import Foundation

/// The text of a WhatsApp message.
struct WhatsAppMessage: Equatable {
    var text: String
    /// How many highlighted passages it has; with none, the snapped passages stand in.
    var highlightCount: Int
    /// Cut short to fit WhatsApp; the PDF should go along with it.
    var isTruncated: Bool
}

/// Formats the page's highlights as a WhatsApp message, as Article Saver does:
///
/// ```
/// *Title*
///
/// *First highlighted passage*
///
/// …
///
/// *Second passage*
/// ```
///
/// Highlights are bold; notes stay out. With no highlights, the snapped passages go
/// unformatted, and with no passages either, the page as written.
enum WhatsAppFormatter {
    /// WhatsApp cuts off longer messages at about 65,000 characters.
    static let maxLength = 60_000
    static let truncationNote = "…\n\n(continued in the attached PDF)"
    static let separator = "\n\n…\n\n"

    static func message(page: String, title: String) -> WhatsAppMessage {
        let header = bold(collapse(PDFExporter.displayTitle(title)))
        let highlights = Highlights.passages(in: page)
        var body = highlights
            .map { $0.map { bold(collapse($0)) }.filter { !$0.isEmpty }.joined(separator: "\n\n") }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
        if body.isEmpty {
            body = PDFExporter.blocks(of: page).compactMap { block in
                if case .passage(let text, _) = block { return paragraphs(text) }
                return nil
            }.joined(separator: separator)
        }
        if body.isEmpty {
            body = paragraphs(page)
        }

        var isTruncated = false
        let fixedLength = header.count + truncationNote.count + 2
        if fixedLength + body.count > maxLength {
            body = String(body.prefix(max(0, maxLength - fixedLength))) + truncationNote
            isTruncated = true
        }
        let text = [header, body].filter { !$0.isEmpty }.joined(separator: "\n\n")
        return WhatsAppMessage(text: text, highlightCount: highlights.count, isTruncated: isTruncated)
    }

    /// Text without quote or highlight markers, one blank line between paragraphs.
    private static func paragraphs(_ text: String) -> String {
        text.split(separator: "\n")
            .map { line in Highlights.parse(line).content.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// Puts `*` around the text so WhatsApp shows it in bold.
    static func bold(_ text: String) -> String {
        text.isEmpty ? text : "*\(text)*"
    }

    /// Runs of whitespace (including newlines) become one space.
    static func collapse(_ text: String) -> String {
        text.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespaces)
    }
}
