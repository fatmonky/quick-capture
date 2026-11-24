import Foundation
import Observation

/// Holds the single text-space that every capture is appended to, and its hashtags,
/// and keeps them saved as plain text files.
@MainActor
@Observable
final class CaptureStore {
    static let separator = "\n\n"

    nonisolated static var defaultFileURL: URL {
        URL.documentsDirectory.appending(path: "capture.txt")
    }

    var text: String {
        didSet { scheduleSave() }
    }

    /// The note's hashtags, without #, saved beside the text.
    var tags: [String] {
        didSet { saveTags() }
    }

    /// Increments on every successful append (not on manual edits), so the UI
    /// can react to new captures — haptics, scrolling to the end.
    private(set) var appendCount = 0

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var tagsURL: URL { Self.tagsURL(for: fileURL) }
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(fileURL: URL = CaptureStore.defaultFileURL) {
        self.fileURL = fileURL
        self.text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        self.tags = NoteTags.parse((try? String(contentsOf: Self.tagsURL(for: fileURL), encoding: .utf8)) ?? "")
    }

    /// Appends a capture to the end of the text-space, separated from
    /// existing text by a blank line. Empty or whitespace-only input is ignored.
    func append(_ snippet: String) {
        let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let existing = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = existing.isEmpty ? trimmed : existing + Self.separator + trimmed
        appendCount += 1
    }

    /// Empties the page and takes its tags off, ready for the next note.
    func clear() {
        text = ""
        tags = []
    }

    /// Writes immediately, cancelling any pending debounced save.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("CaptureStore: failed to save – \(error)")
        }
    }

    /// `capture.txt` keeps its tags in `capture-tags.txt`.
    nonisolated static func tagsURL(for fileURL: URL) -> URL {
        fileURL.deletingLastPathComponent()
            .appending(path: fileURL.deletingPathExtension().lastPathComponent + "-tags.txt")
    }

    private func saveTags() {
        do {
            try NoteTags.display(tags).write(to: tagsURL, atomically: true, encoding: .utf8)
        } catch {
            print("CaptureStore: failed to save tags – \(error)")
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
}
