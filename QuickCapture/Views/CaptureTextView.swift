import SwiftUI
import UIKit

/// The editable text-space. Wraps `UITextView` so the app can scroll to the
/// newest capture after each append, which SwiftUI's `TextEditor` can't do,
/// and so snapped quotes can look different from your own notes.
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
        Self.style(textView)
        context.coordinator.lastScrollTrigger = scrollToEndTrigger
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self

        if textView.text != text {
            textView.text = text
            Self.style(textView)
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

    /// Quotes (lines starting with `>`) are in italics and a softer colour, with the
    /// `>` marker faded; everything else is plain. Highlights are yellow, with their
    /// `==` markers faded. Only attributes change, so the cursor stays put.
    static func style(_ textView: UITextView) {
        let body = UIFont.preferredFont(forTextStyle: .body)
        let plain: [NSAttributedString.Key: Any] = [.font: body, .foregroundColor: UIColor.label]
        let storage = textView.textStorage
        storage.beginEditing()
        storage.setAttributes(plain, range: NSRange(location: 0, length: storage.length))
        let string = storage.string as NSString
        for line in NoteFormat.lineRanges(in: storage.string) {
            if line.isQuote {
                storage.addAttributes([.font: body.withTraits(.traitItalic),
                                       .foregroundColor: UIColor.secondaryLabel], range: line.range)
                storage.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel,
                                     range: NSRange(location: line.range.location, length: line.markerLength))
            }
            for span in Highlights.parse(string.substring(with: line.range)).written {
                let offset = line.range.location
                storage.addAttributes([.backgroundColor: highlightColor, .foregroundColor: UIColor.label],
                                      range: NSRange(location: offset + span.text.location, length: span.text.length))
                for marker in [span.open, span.close] {
                    storage.addAttribute(.foregroundColor, value: UIColor.quaternaryLabel,
                                         range: NSRange(location: offset + marker.location, length: marker.length))
                }
            }
        }
        storage.endEditing()
        textView.typingAttributes = plain
    }

    static let highlightColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0.84, blue: 0.04, alpha: 0.4)
            : UIColor(red: 1, green: 0.894, blue: 0.361, alpha: 1)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CaptureTextView
        var lastScrollTrigger = 0

        init(parent: CaptureTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            CaptureTextView.style(textView)
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isEditing { parent.isEditing = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isEditing { parent.isEditing = false }
        }

        /// Select text to highlight it (and add a note); with the cursor or selection
        /// on a highlight, add a note to it or remove it.
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            let text = textView.text ?? ""
            var actions: [UIMenuElement] = []
            if Highlights.isHighlighted(text, selection: range) {
                actions = [
                    UIAction(title: "Add Note", image: UIImage(systemName: "note.text.badge.plus")) { [weak self] _ in
                        self?.apply(Highlights.addNote(text, at: NSMaxRange(range)), to: textView)
                    },
                    UIAction(title: "Remove Highlight", image: UIImage(systemName: "highlighter"),
                             attributes: .destructive) { [weak self] _ in
                        if let edit = Highlights.removeHighlights(text, selection: range) { self?.apply(edit, to: textView) }
                    },
                ]
            } else if range.length > 0, let edit = Highlights.highlight(text, selection: range) {
                actions = [
                    UIAction(title: "Highlight", image: UIImage(systemName: "highlighter")) { [weak self] _ in
                        self?.apply(edit, to: textView)
                    },
                    UIAction(title: "Highlight & Note", image: UIImage(systemName: "note.text.badge.plus")) { [weak self] _ in
                        self?.apply(Highlights.addNote(edit.text, at: edit.cursor), to: textView)
                    },
                ]
            }
            guard !actions.isEmpty else { return nil }
            return UIMenu(children: [UIMenu(options: .displayInline, children: actions)] + suggestedActions)
        }

        private func apply(_ edit: Highlights.Edit, to textView: UITextView) {
            // As a text input edit, so it can be undone (shake, or three-finger swipe).
            if let all = textView.textRange(from: textView.beginningOfDocument, to: textView.endOfDocument) {
                textView.replace(all, withText: edit.text)
            }
            textView.selectedRange = NSRange(location: edit.cursor, length: 0)
            CaptureTextView.style(textView)
            parent.text = textView.text
            if !textView.isFirstResponder { textView.becomeFirstResponder() }
            textView.scrollRangeToVisible(textView.selectedRange)
        }
    }
}
