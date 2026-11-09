import AppKit
import SwiftUI

/// One choice in a confirmation.
public struct ConfirmChoice: Identifiable {
    public let id = UUID()
    public let label: String
    public let symbol: String
    public let destructive: Bool
    public let run: @MainActor () -> Void
    public init(_ label: String, symbol: String, destructive: Bool = false, run: @escaping @MainActor () -> Void = {}) {
        self.label = label
        self.symbol = symbol
        self.destructive = destructive
        self.run = run
    }
}

/// Every confirmation in the app (Ahmed, 2026-11-05: visual, animated, keyboard driven): a coloured icon tile, a large title and the consequence, then the choices as glass tiles with their keys.
/// ← → move between choices, Return runs the highlighted one, Esc cancels, ⌘Return runs the last (the confirm) at once.
/// The first choice is the safe one and starts highlighted, so Return alone never destroys anything.
public struct ConfirmCard: View {
    let title: String
    let message: String
    let symbol: String
    let choices: [ConfirmChoice]
    let cancel: () -> Void
    @State private var selected = 0
    @State private var shown = false
    @State private var monitor: Any?
    @Environment(\.accessibilityReduceMotion) private var reduce

    public init(
        title: String, message: String, symbol: String? = nil, choices: [ConfirmChoice], cancel: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.choices = choices
        self.cancel = cancel
        self.symbol =
            symbol ?? (choices.contains(where: \.destructive) ? "exclamationmark.triangle" : "questionmark.circle")
    }

    private var danger: Bool { choices.contains(where: \.destructive) }
    private var hue: Color { danger ? GlassInk.red : GlassInk.blue }

    public var body: some View {
        VStack(spacing: Space.s4) {
            IconTile(symbol, hue: hue, size: 64, bounce: shown)
            VStack(spacing: Space.s2) {
                Text(title).coreFont(size: MacTextSize.large + 4, weight: .bold).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(message).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .coreRise(shown, 1)
            HStack(spacing: Space.s2) {
                ForEach(Array(choices.enumerated()), id: \.element.id) { i, c in
                    ChoiceTile(
                        choice: c, on: i == selected,
                        keys: i == 0 ? "esc" : i == choices.count - 1 ? (c.destructive ? "⌘↩" : "↩") : nil
                    ) { run(i) }
                    .onHover { if $0 { selected = i } }
                }
            }
            .coreRise(shown, 2)
            Text("\(coreArrowKeys()) choose · ↩ run the highlighted · esc cancel").coreFont(size: MacTextSize.meta)
                .foregroundStyle(GlassInk.secondary.opacity(0.8))
        }
        .foregroundStyle(GlassInk.primary)
        .padding(Space.s6)
        .frame(width: Space.s8 * 14)
        .corePanel(radius: Radius.panel + Space.s1, padding: 0)
        .shadow(color: .black.opacity(0.35), radius: 40, y: 16)
        .scaleEffect(shown || reduce ? 1 : 0.97)
        .opacity(shown ? 1 : 0)
        .animation(Motion.modal(shown, reduce), value: shown)
        .animation(Motion.out(Motion.hover), value: selected)
        .onAppear {
            shown = true
            listen()
        }
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) } }
        .coreEscape {
            cancel()
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func run(_ i: Int) {
        guard choices.indices.contains(i) else { return }
        choices[i].run()
    }

    /// The keys, caught before anything else in the window while the card is up.
    private func listen() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            switch e.keyCode {
            case 123: selected = max(selected - 1, 0)  // ←
            case 124, 48: selected = min(selected + 1, choices.count - 1)  // → or Tab
            case 36, 76:  // Return, Enter
                run(e.modifierFlags.contains(.command) ? choices.count - 1 : selected)
            default: return e
            }
            return nil
        }
    }
}

/// A choice as a glass tile: icon, label and its key, lit when highlighted (red when destructive).
public struct ChoiceTile: View {
    let choice: ConfirmChoice
    let on: Bool
    let keys: String?
    let run: () -> Void
    public init(choice: ConfirmChoice, on: Bool, keys: String?, run: @escaping () -> Void) {
        self.choice = choice
        self.on = on
        self.keys = keys
        self.run = run
    }
    public var body: some View {
        let hue = choice.destructive ? GlassInk.red : GlassInk.blue
        Button(action: run) {
            HStack(spacing: Space.s2) {
                Image(systemName: choice.symbol).coreFont(size: MacTextSize.body, weight: .semibold)
                    .coreEnterBounce(on)
                Text(choice.label).coreFont(size: MacTextSize.body, weight: .semibold)
                if let keys {
                    Text(keys).coreFont(size: MacTextSize.meta, weight: .medium, design: .rounded)
                        .padding(.horizontal, 6).frame(minHeight: 20)
                        .background(.white.opacity(0.14), in: coreShape(5))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                on ? hue.opacity(choice.destructive ? 0.85 : 0.6) : GlassInk.well, in: coreShape(Radius.control + 2)
            )
            .animation(Motion.out(Motion.hover), value: on)
            .overlay {
                coreShape(Radius.control + 2).strokeBorder(on ? .white.opacity(0.4) : GlassInk.wellEdge, lineWidth: 1)
            }
            .contentShape(coreShape(Radius.control + 2))
        }
        .buttonStyle(CoreTilePress())
        .accessibilityLabel(choice.label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A modal that stands in for content (a terminal that needs Touch ID, one that ended): the confirmation card's look,
/// without taking the window's keys. The primary choice answers Return.
public struct ModalCard: View {
    let title: String
    let message: String
    let note: String?
    let symbol: String
    let hue: Color
    let choices: [(choice: ConfirmChoice, primary: Bool)]
    @State private var shown = false
    @State private var hovered: Int?
    @Environment(\.accessibilityReduceMotion) private var reduce
    public init(
        title: String, message: String, note: String? = nil, symbol: String, hue: Color,
        choices: [(choice: ConfirmChoice, primary: Bool)]
    ) {
        self.title = title
        self.message = message
        self.note = note
        self.symbol = symbol
        self.hue = hue
        self.choices = choices
    }
    public var body: some View {
        VStack(spacing: Space.s3) {
            IconTile(symbol, hue: hue, size: 56, bounce: shown)
            Text(title).coreFont(size: MacTextSize.large + 2, weight: .bold).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                Text(note).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .multilineTextAlignment(.center)
            }
            // The lead choice (the primary, else the first) answers Return; the others ⌘1, ⌘2… Every key is on its tile.
            let lead = choices.firstIndex { $0.primary } ?? 0
            HStack(spacing: Space.s2) {
                ForEach(Array(choices.enumerated()), id: \.element.choice.id) { i, c in
                    let n = i < lead ? i + 1 : i
                    ChoiceTile(
                        choice: c.choice, on: hovered == nil ? i == lead : hovered == i,
                        keys: i == lead ? "↩" : "⌘\(n)"
                    ) {
                        c.choice.run()
                    }
                    .keyboardShortcut(
                        i == lead
                            ? KeyboardShortcut.defaultAction
                            : KeyboardShortcut(KeyEquivalent(Character("\(min(n, 9))")), modifiers: .command)
                    )
                    .onHover { hovered = $0 ? i : nil }
                }
            }
            .padding(.top, Space.s1)
            .coreRise(shown, 1)
        }
        .foregroundStyle(GlassInk.primary)
        .padding(Space.s5)
        .frame(maxWidth: Space.s8 * 13)
        .corePanel(radius: Radius.panel + Space.s1, padding: 0)
        .scaleEffect(shown || reduce ? 1 : 0.97)
        .opacity(shown ? 1 : 0)
        .animation(Motion.modal(shown, reduce), value: shown)
        .animation(Motion.out(Motion.hover), value: hovered)
        .onAppear { shown = true }
        .accessibilityElement(children: .contain)
    }
}

/// A modal's picture and colour from its title, so every dialog has one without each call site choosing.
public enum ModalLook {
    public static func of(_ title: String) -> (symbol: String, hue: Color) {
        let t = title.lowercased()
        func has(_ words: String...) -> Bool { words.contains { t.contains($0) } }
        if t.hasPrefix("lend ") { return ("key.horizontal", GlassInk.orange) }  // not "end "
        if has("revoke", "remove", "delete", "forget", "kill", "end ", "end this", "stop") {
            return ("trash", GlassInk.red)
        }
        if has("rename") { return ("pencil", GlassInk.blue) }
        if has("may do", "access", "scope") { return ("lock.shield", GlassInk.violet) }
        if has("secret", "lease") { return ("key.horizontal", GlassInk.orange) }
        if has("pool") { return ("square.stack.3d.up", GlassInk.violet) }
        if has("account", "connect") { return ("person.crop.circle.badge.plus", GlassInk.green) }
        if has("device", "pair") { return ("laptopcomputer.and.iphone", GlassInk.blue) }
        if has("terminal") { return ("terminal", GlassInk.slate) }
        if has("session", "agent") { return ("sparkles", GlassInk.violet) }
        if has("switch", "setting") { return ("slider.horizontal.3", GlassInk.blue) }
        if has("add", "new", "create") { return ("plus.circle", GlassInk.green) }
        return ("sparkles", GlassInk.blue)
    }
}

/// The header every dialog shares: its icon tile (bouncing in), a big title, and an optional close at the right.
public struct ModalHeader: View {
    let title: String
    let symbol: String?
    let close: (() -> Void)?
    @State private var shown = false
    public init(_ title: String, symbol: String? = nil, close: (() -> Void)? = nil) {
        self.title = title
        self.symbol = symbol
        self.close = close
    }
    public var body: some View {
        let look = ModalLook.of(title)
        HStack(spacing: Space.s3) {
            IconTile(symbol ?? look.symbol, hue: look.hue, size: 44, bounce: shown)
            Text(title).coreFont(size: MacTextSize.large + 2, weight: .bold).accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.s2)
            if let close { CoreIconButton(symbol: "xmark", label: "Close", action: close) }
        }
        .onAppear { shown = true }
    }
}

extension View {
    /// The modal entrance: opacity and a 0.97 scale on the UI ease, 150 ms out; Reduce Motion fades only.
    public func coreModalEntrance() -> some View { modifier(ModalEntrance()) }
}

private struct ModalEntrance: ViewModifier {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content.scaleEffect(shown || reduce ? 1 : 0.97).opacity(shown ? 1 : 0)
            .animation(Motion.modal(shown, reduce), value: shown)
            .onAppear { shown = true }
    }
}
