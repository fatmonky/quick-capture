import UIKit
import Vision

/// Extracts text from photos of printed pages using on-device Vision OCR.
enum TextRecognizer {
    /// One recognized line of text. `box` is Vision's normalized bounding box
    /// (0–1, origin at the bottom-left of the page).
    struct Line: Equatable {
        var text: String
        var box: CGRect
    }

    /// Recognizes the text in each image, joining pages with a blank line.
    static func recognize(_ images: [UIImage]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            var pages: [String] = []
            for image in images {
                let page = assemble(try recognizeLines(in: image))
                if !page.isEmpty { pages.append(page) }
            }
            return pages.joined(separator: "\n\n")
        }.value
    }

    static func recognizeLines(in image: UIImage) throws -> [Line] {
        guard let cgImage = image.cgImage else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: CGImagePropertyOrientation(image.imageOrientation)
        )
        try handler.perform([request])

        return (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map {
                Line(text: $0.string, box: observation.boundingBox)
            }
        }
    }

    /// Turns OCR lines (in Vision's reading order) back into flowing text:
    /// - lines that wrap within a paragraph are joined with a space,
    ///   re-joining words hyphenated across the line break;
    /// - a line that stops well short of the right margin ends with a line break
    ///   (end of a paragraph, list item or heading);
    /// - a large vertical gap becomes a blank line.
    static func assemble(_ rawLines: [Line]) -> String {
        let lines = rawLines
            .map { Line(text: $0.text.trimmingCharacters(in: .whitespaces), box: $0.box) }
            .filter { !$0.text.isEmpty }
        guard let first = lines.first else { return "" }

        let heights = lines.map(\.box.height).sorted()
        let lineHeight = heights[heights.count / 2]
        let right = lines.map(\.box.maxX).max() ?? 1
        let left = lines.map(\.box.minX).min() ?? 0
        let span = right - left

        var result = first.text
        for (previous, line) in zip(lines, lines.dropFirst()) {
            let gap = previous.box.minY - line.box.maxY
            let endedShort = previous.box.maxX < right - span * 0.15

            if gap > lineHeight * 0.8 || gap < -lineHeight * 0.5 {
                // Big gap, or the next line isn't below (new column/block).
                result += "\n\n" + line.text
            } else if endedShort {
                result += "\n" + line.text
            } else {
                result = joinWrapped(result, line.text)
            }
        }
        return result
    }

    private static func joinWrapped(_ text: String, _ next: String) -> String {
        let beforeHyphen = text.dropLast().last
        if text.hasSuffix("-"), beforeHyphen?.isLetter == true, next.first?.isLowercase == true {
            return text.dropLast() + next
        }
        return text + " " + next
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
