import UIKit
import Vision

/// Extracts text from photos of printed pages using on-device Vision OCR.
enum TextRecognizer {
    typealias Line = TextLayout.Line

    /// Recognizes the text in each image, joining pages with a blank line.
    static func recognize(_ images: [UIImage]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            var pages: [String] = []
            for image in images {
                let page = TextLayout.assemble(try recognizeLines(in: image))
                if !page.isEmpty { pages.append(page) }
            }
            return pages.joined(separator: "\n\n")
        }.value
    }

    /// Recognizes the text in one image, keeping only lines centred inside
    /// `region` (a fraction of the image, origin top-left) when one is given.
    static func recognize(_ image: UIImage, within region: CGRect?) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            var lines = try recognizeLines(in: image)
            if let region {
                lines = TextLayout.lines(lines, centredIn: region)
            }
            return TextLayout.assemble(lines)
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
