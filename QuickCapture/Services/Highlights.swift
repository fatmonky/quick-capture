import Foundation

/// Highlights on the page are written `==like this==`, as Obsidian writes them, and
/// never run past the end of a line. Notes on a passage are plain paragraphs under it.
///
/// Positions are in UTF-16, as UIKit counts them.
enum Highlights {
    static let marker = "=="
    private static let equals: UInt16 = 61

    /// One line of the page, read for its highlights.
    struct Line: Equatable {
        /// The quote marker (`> `), if any.
        var prefix: String
        /// The text without highlight markers.
        var content: String
        /// The highlighted parts of `content`, in order, not touching.
        var highlights: [Range<Int>]
        /// Where each position in the written line falls in `content`.
        var contentIndex: [Int]
        /// Where each highlight's text and markers are in the written line.
        var written: [(open: NSRange, text: NSRange, close: NSRange)]

        static func == (lhs: Line, rhs: Line) -> Bool {
            lhs.prefix == rhs.prefix && lhs.content == rhs.content && lhs.highlights == rhs.highlights
        }

        var units: [UInt16] { Array(content.utf16) }

        func text(of range: Range<Int>) -> String {
            String(decoding: units[range], as: UTF16.self)
        }

        /// The line written out again, with its markers.
        var serialized: String {
            var result = Array(prefix.utf16)
            let units = self.units
            var position = 0
            for range in highlights {
                result += units[position..<range.lowerBound]
                result += Array(marker.utf16) + units[range] + Array(marker.utf16)
                position = range.upperBound
            }
            result += units[position...]
            return String(decoding: result, as: UTF16.self)
        }
    }

    static func parse<S: StringProtocol>(_ line: S) -> Line {
        let line = String(line)
        let prefixLength = NoteFormat.isQuote(line)
            ? line.utf16.count - NoteFormat.unquoted(line).utf16.count : 0
        let raw = Array(line.utf16)
        var content: [UInt16] = []
        var highlights: [Range<Int>] = []
        var written: [(NSRange, NSRange, NSRange)] = []
        var index = Array(repeating: 0, count: raw.count + 1)
        var open: (raw: Int, content: Int)?

        func isMarker(_ i: Int) -> Bool { i + 1 < raw.count && raw[i] == equals && raw[i + 1] == equals }

        var i = prefixLength
        while i < raw.count {
            if isMarker(i) {
                if let start = open, content.count > start.content {
                    highlights.append(start.content..<content.count)
                    written.append((NSRange(location: start.raw, length: 2),
                                    NSRange(location: start.raw + 2, length: i - start.raw - 2),
                                    NSRange(location: i, length: 2)))
                    open = nil
                    index[i] = content.count; index[i + 1] = content.count
                    i += 2
                    continue
                }
                // Opens only if a closing marker follows, with text between.
                if open == nil, ((i + 3)..<raw.count).contains(where: isMarker) {
                    open = (i, content.count)
                    index[i] = content.count; index[i + 1] = content.count
                    i += 2
                    continue
                }
            }
            index[i] = content.count
            content.append(raw[i])
            i += 1
        }
        index[raw.count] = content.count
        return Line(prefix: String(decoding: raw[..<prefixLength], as: UTF16.self),
                    content: String(decoding: content, as: UTF16.self),
                    highlights: highlights, contentIndex: index, written: written)
    }

    /// The text without its highlight markers.
    static func plain<S: StringProtocol>(_ text: S) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in let parsed = parse(line); return parsed.prefix + parsed.content }
            .joined(separator: "\n")
    }

    // MARK: - Editing

    /// An edit to the page: the new text, and where the cursor goes.
    struct Edit: Equatable {
        var text: String
        var cursor: Int
    }

    private struct Lines {
        var lines: [String]
        init(_ text: String) { lines = text.components(separatedBy: "\n") }
        var text: String { lines.joined(separator: "\n") }

        func start(of line: Int) -> Int {
            lines[..<line].reduce(0) { $0 + $1.utf16.count + 1 }
        }

        func end(of line: Int) -> Int { start(of: line) + lines[line].utf16.count }

        /// Each line `range` touches, with the part of it (in the line's own positions).
        /// An empty range touches the line it's in.
        func touched(by range: NSRange) -> [(line: Int, local: Range<Int>)] {
            var result: [(Int, Range<Int>)] = []
            var start = 0
            for (index, line) in lines.enumerated() {
                let end = start + line.utf16.count
                let lower = max(range.location, start), upper = min(NSMaxRange(range), end)
                if lower < upper || (range.length == 0 && start <= range.location && range.location <= end) {
                    result.append((index, (lower - start)..<(upper - start)))
                }
                start = end + 1
            }
            return result
        }
    }

    /// Highlights the selected text, line by line, leaving out quote markers and
    /// spaces at either end. Overlapping highlights join. Nil if nothing was picked.
    static func highlight(_ text: String, selection: NSRange) -> Edit? {
        guard selection.length > 0 else { return nil }
        var lines = Lines(text)
        var last: Int?
        for (index, local) in lines.touched(by: selection) {
            var line = parse(lines.lines[index])
            let units = line.units
            var lower = line.contentIndex[local.lowerBound], upper = line.contentIndex[local.upperBound]
            while lower < upper, isSpace(units[lower]) { lower += 1 }
            while upper > lower, isSpace(units[upper - 1]) { upper -= 1 }
            guard lower < upper else { continue }
            line.highlights = merged(line.highlights + [lower..<upper])
            lines.lines[index] = line.serialized
            last = index
        }
        guard let last else { return nil }
        return Edit(text: lines.text, cursor: lines.end(of: last))
    }

    /// Whether the selection (or the cursor) is in or on a highlight.
    static func isHighlighted(_ text: String, selection: NSRange) -> Bool {
        let lines = Lines(text)
        return lines.touched(by: selection).contains { index, local in
            !highlights(in: parse(lines.lines[index]), touching: local).isEmpty
        }
    }

    /// Removes every highlight the selection (or the cursor) is in or on.
    static func removeHighlights(_ text: String, selection: NSRange) -> Edit? {
        var lines = Lines(text)
        var last: Int?
        for (index, local) in lines.touched(by: selection) {
            var line = parse(lines.lines[index])
            let touched = highlights(in: line, touching: local)
            guard !touched.isEmpty else { continue }
            line.highlights.removeAll(where: touched.contains)
            lines.lines[index] = line.serialized
            last = index
        }
        guard let last else { return nil }
        return Edit(text: lines.text, cursor: lines.end(of: last))
    }

    private static func highlights(in line: Line, touching local: Range<Int>) -> [Range<Int>] {
        let lower = line.contentIndex[local.lowerBound], upper = line.contentIndex[local.upperBound]
        return line.highlights.filter { range in
            local.isEmpty ? range.lowerBound <= lower && lower <= range.upperBound
                : range.lowerBound < upper && lower < range.upperBound
        }
    }

    /// Opens an empty paragraph for a note under the passage at `location`, after any
    /// notes already there, and puts the cursor in it.
    static func addNote(_ text: String, at location: Int) -> Edit {
        var lines = Lines(text)
        guard let current = lines.touched(by: NSRange(location: location, length: 0)).last?.line else {
            return Edit(text: text, cursor: location)
        }
        var anchor = current
        if NoteFormat.isQuote(lines.lines[current]) {
            // Past any notes already under this paragraph.
            var scan = current + 1
            while scan < lines.lines.count, !NoteFormat.isQuote(lines.lines[scan]) {
                if !lines.lines[scan].trimmingCharacters(in: .whitespaces).isEmpty { anchor = scan }
                scan += 1
            }
        }

        var rest = Array(lines.lines[(anchor + 1)...])
        if let first = rest.first, first.trimmingCharacters(in: .whitespaces).isEmpty || isBareQuote(first) {
            rest.removeFirst()
        }
        lines.lines = Array(lines.lines[...anchor]) + ["", ""] + (rest.isEmpty ? [] : [""] + rest)
        return Edit(text: lines.text, cursor: lines.start(of: anchor + 2))
    }

    /// A `>` line with nothing on it: the gap between paragraphs of a quote.
    static func isBareQuote(_ line: String) -> Bool {
        NoteFormat.isQuote(line) && NoteFormat.unquoted(line).trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Reading

    /// The highlighted passages, in order. A highlight that runs on from the end of
    /// one paragraph to the start of the next is one passage of several paragraphs.
    static func passages(in page: String) -> [[String]] {
        var passages: [[String]] = []
        var runsOn = false
        for raw in page.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.trimmingCharacters(in: .whitespaces).isEmpty || isBareQuote(line) { continue }
            let parsed = parse(line)
            guard !parsed.highlights.isEmpty else { runsOn = false; continue }
            let units = parsed.units
            let start = units.firstIndex { !isSpace($0) } ?? 0
            let end = (units.lastIndex { !isSpace($0) } ?? -1) + 1
            for (index, range) in parsed.highlights.enumerated() {
                let text = parsed.text(of: range)
                if index == 0, runsOn, range.lowerBound == start, !passages.isEmpty {
                    passages[passages.count - 1].append(text)
                } else {
                    passages.append([text])
                }
                runsOn = index == parsed.highlights.count - 1 && range.upperBound == end
            }
        }
        return passages
    }

    // MARK: - Helpers

    static func merged(_ ranges: [Range<Int>]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    private static func isSpace(_ unit: UInt16) -> Bool { unit == 32 || unit == 9 }
}
