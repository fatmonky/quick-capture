import SwiftUI
import UIKit
import VisionKit

/// Lets SwiftUI drive the live scanner: capture a still for OCR, or read
/// what's currently recognized in the viewfinder.
@MainActor
final class LiveTextScannerController {
    fileprivate weak var scanner: DataScannerViewController?
    fileprivate var items: [RecognizedItem] = []

    /// Live text needs a recent iPhone (A12 or later); false in the simulator.
    static var isSupported: Bool { DataScannerViewController.isSupported }

    func capturePhoto() async throws -> UIImage {
        guard let scanner else { throw LiveTextScannerError.notRunning }
        return try await scanner.capturePhoto()
    }

    /// The text recognized live in the viewfinder, top to bottom.
    var liveText: String {
        items
            .compactMap { item -> (CGPoint, String)? in
                guard case let .text(text) = item else { return nil }
                return (text.bounds.topLeft, text.transcript)
            }
            .sorted { ($0.0.y, $0.0.x) < ($1.0.y, $1.0.x) }
            .map(\.1)
            .joined(separator: "\n")
    }
}

enum LiveTextScannerError: LocalizedError {
    case notRunning

    var errorDescription: String? { "The camera isn't running." }
}

/// Camera viewfinder that finds text as you point it, framing it with yellow
/// corner brackets like the Camera app's Live Text.
struct LiveTextScanner: UIViewControllerRepresentable {
    let controller: LiveTextScannerController
    var onUnavailable: (Error) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: false
        )
        scanner.delegate = context.coordinator
        scanner.overlayContainerView.addSubview(context.coordinator.brackets)
        controller.scanner = scanner
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.parent = self
        guard !scanner.isScanning else { return }
        do {
            try scanner.startScanning()
        } catch {
            onUnavailable(error)
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: LiveTextScanner
        let brackets = FocusBracketsView()

        init(parent: LiveTextScanner) {
            self.parent = parent
            brackets.alpha = 0
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            update(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            update(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            update(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            parent.onUnavailable(error)
        }

        /// Moves the brackets to enclose all the text currently in view.
        private func update(_ items: [RecognizedItem]) {
            parent.controller.items = items

            let textBounds = items.reduce(CGRect.null) { union, item in
                union.union(item.bounds.enclosingRect)
            }
            guard !textBounds.isNull else {
                UIView.animate(withDuration: 0.2) { self.brackets.alpha = 0 }
                return
            }

            let frame = textBounds.insetBy(dx: -14, dy: -14)
            if brackets.alpha == 0 {
                brackets.frame = frame
                UIView.animate(withDuration: 0.2) { self.brackets.alpha = 1 }
            } else {
                UIView.animate(withDuration: 0.2, delay: 0,
                               options: [.beginFromCurrentState, .allowUserInteraction]) {
                    self.brackets.frame = frame
                }
            }
        }
    }
}

/// Four yellow corner brackets, drawn to fill the view's bounds.
final class FocusBracketsView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ rect: CGRect) {
        let lineWidth: CGFloat = 4
        let box = bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let arm = min(32, box.width / 4, box.height / 4)
        let radius = min(8, arm / 2)

        let path = UIBezierPath()
        // Top-left
        path.move(to: CGPoint(x: box.minX, y: box.minY + arm))
        path.addLine(to: CGPoint(x: box.minX, y: box.minY + radius))
        path.addQuadCurve(to: CGPoint(x: box.minX + radius, y: box.minY), controlPoint: CGPoint(x: box.minX, y: box.minY))
        path.addLine(to: CGPoint(x: box.minX + arm, y: box.minY))
        // Top-right
        path.move(to: CGPoint(x: box.maxX - arm, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX - radius, y: box.minY))
        path.addQuadCurve(to: CGPoint(x: box.maxX, y: box.minY + radius), controlPoint: CGPoint(x: box.maxX, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX, y: box.minY + arm))
        // Bottom-right
        path.move(to: CGPoint(x: box.maxX, y: box.maxY - arm))
        path.addLine(to: CGPoint(x: box.maxX, y: box.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: box.maxX - radius, y: box.maxY), controlPoint: CGPoint(x: box.maxX, y: box.maxY))
        path.addLine(to: CGPoint(x: box.maxX - arm, y: box.maxY))
        // Bottom-left
        path.move(to: CGPoint(x: box.minX + arm, y: box.maxY))
        path.addLine(to: CGPoint(x: box.minX + radius, y: box.maxY))
        path.addQuadCurve(to: CGPoint(x: box.minX, y: box.maxY - radius), controlPoint: CGPoint(x: box.minX, y: box.maxY))
        path.addLine(to: CGPoint(x: box.minX, y: box.maxY - arm))

        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        UIColor.systemYellow.setStroke()
        path.stroke()
    }
}

private extension RecognizedItem.Bounds {
    var enclosingRect: CGRect {
        let xs = [topLeft.x, topRight.x, bottomLeft.x, bottomRight.x]
        let ys = [topLeft.y, topRight.y, bottomLeft.y, bottomRight.y]
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}
