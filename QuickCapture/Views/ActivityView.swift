import SwiftUI
import UIKit

/// Something to hand to the share sheet.
struct ShareItem: Identifiable {
    let id = UUID()
    var items: [Any]
}

/// The iOS share sheet, for things `ShareLink` can't share, like rich text.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
