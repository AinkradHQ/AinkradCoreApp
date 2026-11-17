import Foundation

/// Unsent text kept on this Mac (T3): one Markdown file per note, written before every save and deleted once the Core has
/// the text. The file name carries the revision the text was edited from, so a draft found later is merged against the
/// right base: `<note id>.r<rev>.md`, or `day-YYYY-MM-DD.r0.md` for a day whose note the Core does not have yet.
struct LoreDrafts: Sendable {
    let dir: URL

    static var standard: LoreDrafts {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LoreDrafts(dir: support.appendingPathComponent("Ainkrad/lore-drafts", isDirectory: true))
    }

    struct Draft: Equatable {
        let base: Int
        let text: String
    }

    /// Keys are note ids or `day-YYYY-MM-DD`, both made by this app; anything else is never touched.
    static func ok(_ key: String) -> Bool {
        LoreLink.isNoteID(key)
            || (key.hasPrefix("day-") && key.utf8.count == 14
                && key.dropFirst(4).allSatisfy { $0.isNumber || $0 == "-" })
    }

    func write(_ key: String, base: Int, text: String) {
        guard Self.ok(key) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        remove(key)
        try? Data(text.utf8).write(to: dir.appendingPathComponent("\(key).r\(base).md"), options: .atomic)
    }

    func read(_ key: String) -> Draft? {
        guard let name = file(key), let base = Int(name.dropFirst(key.count + 2).dropLast(3)),
            let data = try? Data(contentsOf: dir.appendingPathComponent(name))
        else { return nil }
        return Draft(base: base, text: String(decoding: data, as: UTF8.self))
    }

    func remove(_ key: String) {
        for name in files(key) { try? FileManager.default.removeItem(at: dir.appendingPathComponent(name)) }
    }

    private func file(_ key: String) -> String? { files(key).first }

    private func files(_ key: String) -> [String] {
        guard Self.ok(key) else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasPrefix("\(key).r") && $0.hasSuffix(".md") }
    }
}
