import UIKit

/// Exports the page as an A4 PDF in the style of Article Saver's: the title and
/// date at the top, snapped passages as plain text with only what you highlighted
/// marked, and your notes written out below them with a bar down the side,
/// numbered to match the passage they belong to.
/// The footer has the title and the page number.
enum PDFExporter {
    static let pageSize = CGSize(width: 595.2, height: 841.8) // A4 in points
    static let margin: CGFloat = 48
    static let footerHeight: CGFloat = 24
    static let contentSize = CGSize(width: pageSize.width - 2 * margin,
                                    height: pageSize.height - 2 * margin - footerHeight)
    static let maxPages = 500

    static let highlight = UIColor(red: 1, green: 0.894, blue: 0.361, alpha: 1)  // #ffe45c
    static let noteColor = UIColor(red: 0.78, green: 0.604, blue: 0, alpha: 1)    // #c79a00
    static let muted = UIColor(red: 0.43, green: 0.43, blue: 0.45, alpha: 1)       // #6e6e73
    static let text = UIColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1)       // #1c1c1e
    static let barWidth: CGFloat = 3
    static let noteIndent: CGFloat = 13

    /// Marks the text of a note, so a bar is drawn beside it.
    static let noteBar = NSAttributedString.Key("QuickCaptureNoteBar")

    // MARK: - Reading the page

    /// One part of the page: a snapped passage, a note on the passage above it, or
    /// text written before any passage.
    enum Block: Equatable {
        case passage(String, note: Int?)
        case note(Int, String)
        case text(String)
    }

    /// Quote lines become passages; what follows a passage, in your own words, is
    /// a note on it, numbered.
    static func blocks(of page: String) -> [Block] {
        // Paragraphs: runs of quote lines, or runs of plain lines between blank lines.
        var paragraphs: [(isQuote: Bool, lines: [String])] = []
        var current: (isQuote: Bool, lines: [String])?
        func flush() {
            if let paragraph = current, !paragraph.lines.isEmpty { paragraphs.append(paragraph) }
            current = nil
        }
        for line in page.split(separator: "\n", omittingEmptySubsequences: false) {
            let isQuote = NoteFormat.isQuote(line)
            let content = (isQuote ? NoteFormat.unquoted(line) : String(line)).trimmingCharacters(in: .whitespaces)
            if !isQuote && content.isEmpty { flush(); continue }
            if current?.isQuote != isQuote { flush(); current = (isQuote, []) }
            if !content.isEmpty { current?.lines.append(content) }
        }
        flush()

        var blocks: [Block] = []
        var number = 0
        for paragraph in paragraphs {
            if paragraph.isQuote {
                blocks.append(.passage(paragraph.lines.joined(separator: "\n"), note: nil))
                continue
            }
            let text = paragraph.lines.joined(separator: "\n")
            switch blocks.last {
            case .passage(let passage, nil):
                number += 1
                blocks[blocks.count - 1] = .passage(passage, note: number)
                blocks.append(.note(number, text))
            case .note(let n, let earlier):
                blocks[blocks.count - 1] = .note(n, earlier + "\n\n" + text)
            case .text(let earlier):
                blocks[blocks.count - 1] = .text(earlier + "\n\n" + text)
            default:
                blocks.append(.text(text))
            }
        }
        return blocks
    }

    // MARK: - Laying out

    static func attributedText(page: String, title: String, date: Date) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let title = displayTitle(title)

        let titleStyle = NSMutableParagraphStyle()
        titleStyle.paragraphSpacing = 4
        result.append(NSAttributedString(string: title + "\n", attributes: [
            .font: UIFont.systemFont(ofSize: 20, weight: .bold), .foregroundColor: text, .paragraphStyle: titleStyle,
        ]))
        let metaStyle = NSMutableParagraphStyle()
        metaStyle.paragraphSpacing = 18
        result.append(NSAttributedString(
            string: "Captured \(date.formatted(date: .long, time: .shortened)) · Quick Capture\n",
            attributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: muted, .paragraphStyle: metaStyle]
        ))

        let body = UIFont.systemFont(ofSize: 11)
        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.lineHeightMultiple = 1.25
        bodyStyle.paragraphSpacing = 10
        let noteStyle = bodyStyle.mutableCopy() as! NSMutableParagraphStyle
        noteStyle.firstLineHeadIndent = noteIndent
        noteStyle.headIndent = noteIndent
        noteStyle.lineHeightMultiple = 1.2
        noteStyle.paragraphSpacing = 14
        let labelStyle = noteStyle.mutableCopy() as! NSMutableParagraphStyle
        labelStyle.paragraphSpacing = 2
        let bodyAttributes: [NSAttributedString.Key: Any] = [.font: body, .foregroundColor: text, .paragraphStyle: bodyStyle]

        for block in blocks(of: page) {
            switch block {
            case .passage(let passage, let note):
                // The passage is plain; only what you highlighted is marked. The note's
                // number goes after the last highlight, or at the end of the passage.
                let lines = paragraphs(passage).map { Highlights.parse($0) }
                let numbered = lines.lastIndex { !$0.highlights.isEmpty } ?? lines.count - 1
                for (index, line) in lines.enumerated() {
                    if index > 0 { result.append(NSAttributedString(string: "\n", attributes: bodyAttributes)) }
                    let paragraph = Highlights.attributed(line, attributes: bodyAttributes, highlight: highlight)
                    if let note, index == numbered {
                        let at = line.highlights.last.map(\.upperBound) ?? paragraph.length
                        paragraph.insert(NSAttributedString(string: "\u{2009}\(note)", attributes: [
                            .font: UIFont.systemFont(ofSize: 7, weight: .semibold), .foregroundColor: muted,
                            .baselineOffset: 4, .paragraphStyle: bodyStyle,
                        ]), at: at)
                    }
                    result.append(paragraph)
                }
            case .note(let number, let note):
                result.append(NSAttributedString(string: "Note \(number)\n", attributes: [
                    .font: UIFont.systemFont(ofSize: 8, weight: .semibold), .foregroundColor: muted,
                    .paragraphStyle: labelStyle, noteBar: true,
                ]))
                result.append(highlighted(note, attributes: [
                    .font: UIFont.systemFont(ofSize: 10), .foregroundColor: text, .paragraphStyle: noteStyle, noteBar: true,
                ]))
            case .text(let plain):
                result.append(highlighted(plain, attributes: bodyAttributes))
            }
            result.append(NSAttributedString(string: "\n", attributes: [.font: body, .paragraphStyle: bodyStyle]))
        }
        return result
    }

    /// Paragraphs of your own words, with any highlights in them marked.
    private static func highlighted(_ text: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, line) in paragraphs(text).enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n", attributes: attributes)) }
            result.append(Highlights.attributed(Highlights.parse(line), attributes: attributes, highlight: highlight))
        }
        return result
    }

    /// Paragraph spacing keeps paragraphs apart, so blank lines are dropped.
    private static func paragraphs(_ text: String) -> [String] {
        text.split(separator: "\n").map(String.init)
    }

    // MARK: - Rendering

    static func pdfData(page: String, title: String, date: Date = .now) -> Data {
        let storage = NSTextStorage(attributedString: attributedText(page: page, title: title, date: date))
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        // One text container per page, until all the text is laid out.
        var containers: [NSTextContainer] = []
        repeat {
            let container = NSTextContainer(size: contentSize)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            containers.append(container)
        } while NSMaxRange(layoutManager.glyphRange(for: containers.last!)) < layoutManager.numberOfGlyphs
            && containers.count < maxPages

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: displayTitle(title),
            kCGPDFContextCreator as String: "Quick Capture",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        return renderer.pdfData { context in
            let origin = CGPoint(x: margin, y: margin)
            for (index, container) in containers.enumerated() {
                context.beginPage()
                let glyphs = layoutManager.glyphRange(for: container)
                drawNoteBars(in: glyphs, layoutManager: layoutManager, storage: storage, origin: origin)
                layoutManager.drawBackground(forGlyphRange: glyphs, at: origin)
                layoutManager.drawGlyphs(forGlyphRange: glyphs, at: origin)
                drawFooter(page: index + 1, of: containers.count, title: displayTitle(title))
            }
        }
    }

    /// A bar down the left of each note, as in Article Saver's PDFs.
    private static func drawNoteBars(in glyphs: NSRange, layoutManager: NSLayoutManager,
                                     storage: NSTextStorage, origin: CGPoint) {
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        noteColor.setFill()
        storage.enumerateAttribute(noteBar, in: characters) { value, range, _ in
            guard value != nil else { return }
            let noteGlyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var top = CGFloat.infinity, bottom = -CGFloat.infinity
            layoutManager.enumerateLineFragments(forGlyphRange: NSIntersectionRange(noteGlyphs, glyphs)) { _, used, _, _, _ in
                top = min(top, used.minY)
                bottom = max(bottom, used.maxY)
            }
            guard top < bottom else { return }
            UIRectFill(CGRect(x: origin.x, y: origin.y + top, width: barWidth, height: bottom - top))
        }
    }

    /// The title on the left, "page / pages" on the right.
    private static func drawFooter(page: Int, of pages: Int, title: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.darkGray,
        ]
        let pageText = NSAttributedString(string: "\(page) / \(pages)", attributes: attributes)
        let pageTextSize = pageText.size()
        let y = pageSize.height - margin - pageTextSize.height
        pageText.draw(at: CGPoint(x: pageSize.width - margin - pageTextSize.width, y: y))

        var titleAttributes = attributes
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        titleAttributes[.paragraphStyle] = truncating
        NSAttributedString(string: title, attributes: titleAttributes)
            .draw(in: CGRect(x: margin, y: y, width: contentSize.width - pageTextSize.width - 16, height: pageTextSize.height))
    }

    // MARK: - File

    static func displayTitle(_ title: String) -> String {
        let title = MarkdownFormatter.collapse(title)
        return title.isEmpty ? MarkdownFormatter.defaultTitle : title
    }

    /// The title as a file name: no path characters, at most 80 characters.
    static func fileName(for title: String) -> String {
        let cleaned = displayTitle(title)
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".")))
        return "\(cleaned.isEmpty ? MarkdownFormatter.defaultTitle : String(cleaned.prefix(80))).pdf"
    }

    /// Writes the PDF to a new temporary folder, for the share sheet.
    static func temporaryFile(page: String, title: String, date: Date = .now) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "Exports/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: fileName(for: title), directoryHint: .notDirectory)
        try pdfData(page: page, title: title, date: date).write(to: destination, options: .atomic)
        return destination
    }
}
