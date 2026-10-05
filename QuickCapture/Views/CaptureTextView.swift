import SwiftUI
import UIKit

/// The editable text-space. Wraps `UITextView` so the app can scroll to the
/// newest capture after each append, which SwiftUI's `TextEditor` can't do.
struct CaptureTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool
    /// Changes whenever a capture is appended; each change scrolls to the end.
    var scrollToEndTrigger: Int

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 16, bottom: 16, right: 16)
        textView.textContainer.lineFragmentPadding = 0
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.text = text
        context.coordinator.lastScrollTrigger = scrollToEndTrigger
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self

        if textView.text != text {
            textView.text = text
        }

        // Change focus after this SwiftUI update finishes. Dismissing the
        // keyboard mid-update leaves the capture bar stranded where the
        // keyboard was, because the layout misses the keyboard hiding.
        if isEditing, !textView.isFirstResponder {
            DispatchQueue.main.async { textView.becomeFirstResponder() }
        } else if !isEditing, textView.isFirstResponder {
            DispatchQueue.main.async { textView.resignFirstResponder() }
        }

        if context.coordinator.lastScrollTrigger != scrollToEndTrigger {
            context.coordinator.lastScrollTrigger = scrollToEndTrigger
            // Wait a run-loop turn so layout reflects the new text (and any
            // capture sheet has started dismissing).
            DispatchQueue.main.async {
                textView.layoutIfNeeded()
                textView.scrollRangeToVisible(NSRange(location: (textView.text as NSString).length, length: 0))
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CaptureTextView
        var lastScrollTrigger = 0

        init(parent: CaptureTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isEditing { parent.isEditing = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isEditing { parent.isEditing = false }
        }
    }
}
