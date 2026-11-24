import Foundation

/// Hashtags on the note, as Article Saver has them: typed as "#ai #building",
/// kept lowercase without the #. Tags used before are remembered, to suggest again.
enum NoteTags {
    private static let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
    private static let historyKey = "tagHistory"

    /// The tags in what was typed: lowercase, without #, each one once, in order.
    /// Spaces, commas and any other punctuation separate them.
    static func parse(_ text: String) -> [String] {
        var tags: [String] = []
        for tag in text.lowercased().components(separatedBy: allowed.inverted) where !tag.isEmpty {
            if !tags.contains(tag) { tags.append(tag) }
        }
        return tags
    }

    /// `tags` as you see them: "#ai #building".
    static func display(_ tags: [String]) -> String {
        tags.map { "#\($0)" }.joined(separator: " ")
    }

    /// The tag being typed at the end of `text`, lowercase, or nil after a space or #.
    static func fragment(in text: String) -> String? {
        let fragment = String(text.unicodeScalars.reversed().prefix { allowed.contains($0) }.reversed().map(Character.init))
        return fragment.isEmpty ? nil : fragment.lowercased()
    }

    /// Tags to suggest while typing `text`. With a tag half typed, the ones that start
    /// with it, then the ones with a later word that does ("rec" finds "system_of_record"),
    /// leaving out tags already typed. Otherwise every tag used before.
    static func suggestions(for text: String, from used: [String]) -> [String] {
        guard let fragment = fragment(in: text) else { return used }
        let chosen = parse(String(text.dropLast(fragment.count)))
        let candidates = used.filter { !chosen.contains($0) }
        let starting = candidates.filter { $0.hasPrefix(fragment) }
        let laterWord = candidates.filter { tag in
            !tag.hasPrefix(fragment)
                && tag.split(whereSeparator: { "_-".contains($0) }).dropFirst().contains { $0.hasPrefix(fragment) }
        }
        return starting + laterWord
    }

    /// `text` with the half-typed tag at its end replaced by `tag`, ready for the next one.
    static func completing(_ text: String, with tag: String) -> String {
        let typed = fragment(in: text)?.count ?? 0
        return String(text.dropLast(typed)) + tag + " #"
    }

    // MARK: - Tags used before

    /// Every tag used before, most used first, then alphabetically.
    static func used(in defaults: UserDefaults = .standard) -> [String] {
        let counts = defaults.dictionary(forKey: historyKey) as? [String: Int] ?? [:]
        return counts.keys.sorted { (counts[$0]!, $1) > (counts[$1]!, $0) }
    }

    /// Counts each of `tags` as used once more.
    static func remember(_ tags: [String], in defaults: UserDefaults = .standard) {
        var counts = defaults.dictionary(forKey: historyKey) as? [String: Int] ?? [:]
        for tag in tags { counts[tag, default: 0] += 1 }
        defaults.set(counts, forKey: historyKey)
    }
}
