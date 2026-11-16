import AppKit
import CoreUI
import SwiftUI

/// Every action on the session screen has a key (Ahmed, 2026-11-15). One table, read by the pane (SwiftUI keys) and by the
/// message field (AppKit key equivalents, which the pane never hears while the field has the cursor), and listed by ⌘/.
enum SessionShortcut: CaseIterable {
    case find, findNext, findPrevious
    case goAhead, changePlan, stopTurn, endSession
    case terminal, openIn, review, attach, model, compact, copyAnswer
    case expandSteps, collapseSteps, details, sidebar, shortcuts

    /// The key (as AppKit and SwiftUI both spell it: "\r" for Return, the private-use arrows) and its modifiers.
    var chord: (key: Character, mods: EventModifiers) {
        switch self {
        case .find: ("f", .command)
        case .findNext: ("g", .command)
        case .findPrevious: ("g", [.command, .shift])
        case .goAhead: ("\r", .command)
        case .changePlan: ("\r", [.command, .shift])
        case .stopTurn: (".", .command)
        case .endSession: ("e", [.command, .shift])
        case .terminal: ("t", [.command, .shift])
        case .openIn: ("o", [.command, .shift])
        case .review: ("r", [.command, .shift])
        case .attach: ("a", [.command, .shift])
        case .model: ("m", [.command, .shift])
        case .compact: ("k", [.command, .shift])
        case .copyAnswer: ("c", [.command, .shift])
        case .expandSteps: ("\u{F703}", [.command, .option])
        case .collapseSteps: ("\u{F702}", [.command, .option])
        case .details: ("i", [.command, .option])
        case .sidebar: ("s", [.command, .control])
        case .shortcuts: ("/", .command)
        }
    }

    /// The chord as the menus print it: "⇧⌘R".
    var label: String {
        let (k, m) = chord
        let key: String =
            switch k {
            case "\r": "↩"
            case "\u{F703}": "→"
            case "\u{F702}": "←"
            default: String(k).uppercased()
            }
        return (m.contains(.control) ? "⌃" : "") + (m.contains(.option) ? "⌥" : "") + (m.contains(.shift) ? "⇧" : "")
            + (m.contains(.command) ? "⌘" : "") + key
    }

    var title: String {
        switch self {
        case .find: "Find in the conversation"
        case .findNext: "Next match"
        case .findPrevious: "Previous match"
        case .goAhead: "Approve, or go ahead with the plan"
        case .changePlan: "Change the plan"
        case .stopTurn: "Stop the turn"
        case .endSession: "End the session…"
        case .terminal: "Terminal here"
        case .openIn: "Open in…"
        case .review: "Review the changes"
        case .attach: "Attach a file…"
        case .model: "Switch the model"
        case .compact: "Compact the context"
        case .copyAnswer: "Copy the last answer"
        case .expandSteps: "Open all tool steps"
        case .collapseSteps: "Fold all tool steps"
        case .details: "Show or hide the details"
        case .sidebar: "Show or hide your other sessions"
        case .shortcuts: "Keyboard shortcuts"
        }
    }

    /// The shortcut a key press means, if any. Letters compare without case (⇧ turns "g" into "G").
    static func match(_ key: Character, _ mods: EventModifiers) -> SessionShortcut? {
        let k = Character(String(key).lowercased())
        let m = mods.intersection([.command, .shift, .option, .control])
        return allCases.first { $0.chord.key == k && $0.chord.mods == m }
    }

    /// The same, from an AppKit key event (the message field's key equivalents).
    static func match(_ event: NSEvent) -> SessionShortcut? {
        guard let k = event.charactersIgnoringModifiers?.first else { return nil }
        let f = event.modifierFlags
        var m: EventModifiers = []
        if f.contains(.command) { m.insert(.command) }
        if f.contains(.shift) { m.insert(.shift) }
        if f.contains(.option) { m.insert(.option) }
        if f.contains(.control) { m.insert(.control) }
        return match(k, m)
    }
}

/// What one session screen has open, shared by its parts so a key can open what a click opens.
@MainActor @Observable
final class SessionUI {
    var openIn = false
    var modelMenu = false
    var reviewing = false
    var shortcuts = false
    /// Bumped to ask the composer for its file picker.
    var attach = 0
    /// ⌘ is held: every button shows its key (Ahmed, 2026-11-15), as Safari shows its tab numbers.
    var showKeys = false
    @ObservationIgnored var keysTask: Task<Void, Never>?

    /// Follows the modifier keys: ⌘ held a moment shows the keys; letting go, or pressing a key, hides them.
    func track(_ e: NSEvent, active: Bool) {
        keysTask?.cancel()
        let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard active, e.type == .flagsChanged, f.contains(.command), f.isSubset(of: [.command, .shift, .option]) else {
            if showKeys { showKeys = false }
            return
        }
        keysTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.showKeys = true
        }
    }

    /// The message field itself, so the cursor can be handed to it directly (SwiftUI's focus state drifts).
    @ObservationIgnored weak var field: NSTextView?

    /// Puts the cursor in the message field.
    func focusField() {
        guard let f = field, let w = f.window, w.firstResponder !== f else { return }
        w.makeFirstResponder(f)
    }

    /// Bumped to put the cursor in the message field (Edit, Quote).
    var focusComposer = 0
    /// Open or fold every tool step: bumped with the wanted state.
    var steps = (gen: 0, open: false)
}

extension EnvironmentValues {
    @Entry var sessionUI: SessionUI? = nil
}

/// ⌘/: every key of the session screen, in a pop-up over the conversation. Esc or ⌘/ closes it.
struct ShortcutSheet: View {
    let close: () -> Void
    @Environment(\.corePalette) private var palette

    private static let more: [(String, String)] = [
        ("⌘⌫", "Deny a waiting request"), ("↩", "Send the message (⇧↩ a new line)"),
        ("↑", "Edit your last message (empty field)"),
        ("esc", "Stop the turn, or leave the field"), ("/", "Commands"), ("⌥↑ ⌥↓", "Your previous or next message"),
        ("↓", "Jump to the newest message"), ("R", "Resume or start again"), ("W", "Wake a finished session"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("Keyboard shortcuts").coreFont(size: MacTextSize.body, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                CoreIconButton(symbol: "xmark", label: "Close", action: close).help("Close (Esc)")
            }
            HStack(alignment: .top, spacing: Space.s6) {
                column(SessionShortcut.allCases.map { ($0.label, $0.title) })
                column(Self.more)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: 640)
        // The pop-up frame of the menus (rim and the Look's background), so the conversation never shows through the words.
        .coreFrame(radius: Radius.cardMac + Space.s1, rim: Space.s1, part: .dropdowns)
        .shadow(color: GlassInk.shade(0.3), radius: 24, y: 8)
        .coreEscape {
            close()
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keyboard shortcuts")
    }

    private func column(_ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(spacing: Space.s3) {
                    Text(r.0).coreFont(size: MacTextSize.meta, weight: .semibold).monospacedDigit()
                        .foregroundStyle(palette.text2).frame(width: Space.s8 + Space.s4, alignment: .trailing)
                    Text(r.1).coreFont(size: MacTextSize.body)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A control's key while ⌘ is held (SessionUI.showKeys): it covers the control's own face, inside its bounds, so it never
/// overlaps a neighbour and nothing moves (Ahmed, 2026-11-15); letting go brings the name back. The key is always in the
/// control's tooltip too.
private struct KeyHint: ViewModifier {
    let label: String
    @Environment(\.sessionUI) private var ui
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        let on = ui?.showKeys == true && !label.isEmpty
        content.overlay {
            Text(label).coreFont(size: 11, weight: .semibold, design: .rounded).monospacedDigit()
                .fixedSize()
                .foregroundStyle(GlassInk.primary)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(GlassInk.adaptive(Color(white: 0.16), day: Color(white: 0.96)), in: coreShape(Radius.chip))
                .opacity(on ? 1 : 0)
                .animation(Motion.out(Motion.hover), value: on)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Shows `label` ("⇧⌘T") on this control while ⌘ is held.
    func keyHint(_ label: String) -> some View { modifier(KeyHint(label: label)) }

    /// The same, from the shortcut table.
    func keyHint(_ key: SessionShortcut) -> some View { modifier(KeyHint(label: key.label)) }
}
