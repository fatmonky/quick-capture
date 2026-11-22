import Foundation

/// The folder Markdown notes are saved to (such as an Obsidian inbox on Dropbox),
/// chosen once and remembered. It belongs to another app, so it's kept as a bookmark.
enum MarkdownFolder {
    private static let key = "markdownFolderBookmark"

    static var current: URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: key) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else { return nil }
        if isStale { try? remember(url) }
        return url
    }

    static func remember(_ url: URL) throws {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        UserDefaults.standard.set(try url.bookmarkData(), forKey: key)
    }

    /// Adds the note to `folder` and returns where it went. Never replaces a file.
    @discardableResult
    static func save(_ note: MarkdownNote, in folder: URL) throws -> URL {
        let hasAccess = folder.startAccessingSecurityScopedResource()
        defer { if hasAccess { folder.stopAccessingSecurityScopedResource() } }

        let destination = folder.appending(path: note.fileName, directoryHint: .notDirectory)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: destination, options: [], error: &coordinationError) { url in
            do {
                try Data(note.text.utf8).write(to: url, options: .withoutOverwriting)
            } catch {
                writeError = error
            }
        }
        if let error = coordinationError ?? writeError { throw error }
        return destination
    }

    /// A copy of the note for the share sheet.
    static func temporaryFile(for note: MarkdownNote) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "Exports/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try save(note, in: folder)
    }
}
