import Foundation

/// The release notes of an update, as the appcast carries them: plain text, one change per line, `Title | one line under it`.
/// Anything else (a heading, a blank line, markup) is dropped, so a note can never put markup or links in front of the person.
public struct WhatsNewItem: Equatable, Sendable {
    public var title: String
    public var sub: String
}

public enum WhatsNew {
    public static func parse(_ text: String) -> [WhatsNewItem] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let t = parts.first, !t.isEmpty, !t.contains("<"), t.count <= 80 else { return nil }
            let s = parts.count > 1 && !parts[1].contains("<") ? String(parts[1].prefix(120)) : ""
            return WhatsNewItem(title: t, sub: s)
        }
        .prefix(8).map { $0 }
    }

    /// The sheet's body: a line per change.
    public static func message(_ items: [WhatsNewItem]) -> String {
        items.map { $0.sub.isEmpty ? "• \($0.title)" : "• \($0.title): \($0.sub)" }.joined(separator: "\n")
    }
}

/// The notes of an update that is waiting to install, kept so the first launch of the new version can show them ("Installed
/// last night") once. `take` returns them only when the running version is the one they belong to.
public enum WhatsNewStore {
    private static let key = "ainkrad.update.whatsnew"

    public static func save(version: String, items: [WhatsNewItem], defaults: UserDefaults = .standard) {
        let lines = items.map { "\($0.title) | \($0.sub)" }
        defaults.set(["version": version, "notes": lines.joined(separator: "\n")], forKey: key)
    }

    public static func take(installed current: String, defaults: UserDefaults = .standard) -> (version: String, items: [WhatsNewItem])? {
        guard let d = defaults.dictionary(forKey: key) as? [String: String], d["version"] == current else { return nil }
        defaults.removeObject(forKey: key)
        return (current, WhatsNew.parse(d["notes"] ?? ""))
    }
}
