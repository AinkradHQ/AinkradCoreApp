import Testing

@testable import Lore
@testable import Shell

@MainActor struct LoreKeysTests {
    /// The menu bar's keys (the shell's catalog, plus the menu keys it does not list).
    private var shellKeys: Set<String> {
        var out: Set<String> = ["⌘Q", "⌘Z", "⇧⌘Z", "⌥⌘T", "⌥⌘G", "⌘H", "⌘M"]
        for g in ShortcutCatalog.groups where ["Ainkrad", "File", "View"].contains(g.name) {
            for item in g.items { for k in item.keys.components(separatedBy: " / ") { out.insert(k) } }
        }
        return out
    }

    @Test func everyKeyIsUnique() {
        let labels = (LoreKeys.all + LoreKeys.sheet).map(\.label)
        #expect(Set(labels).count == labels.count)
        let combos = LoreKeys.all.map { "\($0.key)-\($0.modifiers.rawValue)" }
        #expect(Set(combos).count == combos.count)
    }

    @Test func noKeyTakesAMenuKey() {
        // ⌘N is the shell's own New: it runs the active pane's onNew, which is Lore's new note.
        let mine = (LoreKeys.all + LoreKeys.sheet).filter { $0.label != LoreKeys.new.label }
        for k in mine { #expect(!shellKeys.contains(k.label), "\(k.label) \(k.title) takes a menu key") }
        #expect(shellKeys.contains(LoreKeys.new.label))
    }

    @Test func labelsMatchTheirKeys() {
        for k in LoreKeys.all + LoreKeys.sheet {
            #expect(k.label.hasSuffix(String(k.key).uppercased()), "\(k.label) is bound to \(k.key)")
            #expect(k.label.contains("⇧") == k.modifiers.contains(.shift))
            #expect(k.label.contains("⌥") == k.modifiers.contains(.option))
        }
    }

    @Test func listCursorMovesAndStopsAtTheEnds() {
        let ids = ["a", "b", "c"]
        #expect(LoreKeys.next(ids, from: nil, step: 1) == "a")
        #expect(LoreKeys.next(ids, from: nil, step: -1) == "c")
        #expect(LoreKeys.next(ids, from: "a", step: 1) == "b")
        #expect(LoreKeys.next(ids, from: "c", step: 1) == "c")
        #expect(LoreKeys.next(ids, from: "a", step: -1) == "a")
        #expect(LoreKeys.next(ids, from: "gone", step: 1) == "a")
        #expect(LoreKeys.next([], from: nil, step: 1) == nil)
    }
}
