// LoreKeys — every key of the Lore space in one place: the controls bind these, their tooltips and keycaps and the key
// line show them, and a test keeps them unique and clear of the shell's menu keys.
import CoreUI
import SwiftUI

struct LoreKey: Sendable {
    let title: String
    /// As the shell's shortcut sheet writes it (⌃⌥⇧⌘ order): "⇧⌘H".
    let label: String
    let key: Character
    let modifiers: EventModifiers

    init(_ title: String, _ label: String, _ key: Character, _ modifiers: EventModifiers = .command) {
        self.title = title
        self.label = label
        self.key = key
        self.modifiers = modifiers
    }

    /// "Open a note  ⌘O", for `.help`.
    var help: String { "\(title)  \(label)" }
}

enum LoreKeys {
    /// The shell's New (File menu): it runs the active pane's `onNew`, which is Lore's new note.
    static let new = LoreKey("New note", "⌘N", "n")
    static let open = LoreKey("Open a note", "⌘O", "o")
    static let find = LoreKey("Find in the note list", "⌘L", "l")
    static let today = LoreKey("Go to today's note", "⌘D", "d")
    static let dayBefore = LoreKey("Show the day before", "⌘[", "[")
    static let nextDay = LoreKey("Show the next day", "⌘]", "]")
    static let left = LoreKey("Show or hide the note list", "⌘1", "1")
    static let right = LoreKey("Show or hide the outline", "⌘2", "2")
    static let outline = LoreKey("Go to the outline", "⌘3", "3")
    static let versions = LoreKey("Show earlier versions", "⇧⌘H", "h", [.command, .shift])
    static let project = LoreKey("Move to a project", "⇧⌘P", "p", [.command, .shift])
    static let focus = LoreKey("Focus mode", "⌘.", ".")
    static let save = LoreKey("Save now", "⌘S", "s")

    static let all = [new, open, find, today, dayBefore, nextDay, left, right, outline, versions, project, focus, save]

    // The Open a Note dialog (its own keys; ⌘↵ makes a new note, Return opens the picked one, Esc closes).
    static let advancedNew = LoreKey("Choose the project and tags of a new note", "⌥⌘N", "n", [.command, .option])
    static let export = LoreKey("Save the notes as a zip of Markdown files", "⇧⌘E", "e", [.command, .shift])
    static let importNotes = LoreKey("Bring in notes from a repo or Markdown files", "⇧⌘I", "i", [.command, .shift])
    static let sheet = [advancedNew, export, importNotes]

    /// The key line along the bottom of the space.
    static let hints: [(String, String)] = [
        (open.label, "Open"), (find.label, "Find"), ("↑↓ ↵", "Pick"), ("esc", "Back to the note"),
        (today.label, "Today"), ("⌘[ ⌘]", "Days"), ("⌘1 ⌘2", "Sidebars"), (outline.label, "Outline"),
        (versions.label, "Versions"), (focus.label, "Focus"),
    ]

    /// The row after (`step` 1) or before (-1) `cursor` in `ids`; the first or last when there is no cursor yet.
    static func next(_ ids: [String], from cursor: String?, step: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let at = cursor.flatMap(ids.firstIndex(of:)) else { return step > 0 ? ids.first : ids.last }
        return ids[min(max(at + step, 0), ids.count - 1)]
    }
}

extension View {
    /// Runs this control with `k`; the key shows on a Core button and in the tooltip.
    func loreKey(_ k: LoreKey) -> some View {
        keyboardShortcut(KeyEquivalent(k.key), modifiers: k.modifiers).environment(\.coreKeycap, k.label)
    }

    /// ↑ ↓ move the list's cursor, Return runs the row under it, Esc goes back to the note.
    func loreListKeys(
        _ ids: [String], cursor: Binding<String?>, run: @escaping (String) -> Void, back: @escaping () -> Void
    ) -> some View {
        onKeyPress(.downArrow) {
            cursor.wrappedValue = LoreKeys.next(ids, from: cursor.wrappedValue, step: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            cursor.wrappedValue = LoreKeys.next(ids, from: cursor.wrappedValue, step: -1)
            return .handled
        }
        .onKeyPress(.return) {
            guard let c = cursor.wrappedValue, ids.contains(c) else { return .ignored }
            run(c)
            return .handled
        }
        .onKeyPress(.escape) {
            back()
            return .handled
        }
    }
}

/// The keys of the space, quietly along the bottom (the Leyline key line).
struct LoreKeyLine: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            line(LoreKeys.hints)
            line(Array(LoreKeys.hints.prefix(6)))
            line(Array(LoreKeys.hints.prefix(4)))
        }
        .frame(maxWidth: .infinity).frame(height: Space.s6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Keys: " + LoreKeys.hints.map { "\($0.0) \($0.1)" }.joined(separator: ", "))
    }

    private func line(_ hints: [(String, String)]) -> some View {
        HStack(spacing: Space.s4) {
            ForEach(hints, id: \.1) { k, word in
                HStack(spacing: Space.s1 + 2) {
                    CoreKeycap(k)
                    Text(word).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
                .fixedSize()
            }
        }
    }
}
