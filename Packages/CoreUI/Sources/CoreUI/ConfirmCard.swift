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

/// Every confirmation in the app (Ahmed, 2026-11-05: visual, animated, keyboard driven): a coloured icon tile that
/// pulses for a destructive choice, a large title and the consequence, then the choices as glass tiles with their keys.
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
                .symbolEffect(.pulse, options: .repeating, isActive: danger && !reduce)
                .shadow(color: hue.opacity(0.5), radius: 18)
                .scaleEffect(shown || reduce ? 1 : 0.6)
            VStack(spacing: Space.s2) {
                Text(title).font(.system(size: MacTextSize.large + 4, weight: .bold)).multilineTextAlignment(.center)
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
            Text("← → choose · ↩ run the highlighted · esc cancel").font(.system(size: MacTextSize.meta))
                .foregroundStyle(GlassInk.secondary.opacity(0.8))
        }
        .foregroundStyle(GlassInk.primary)
        .padding(Space.s6)
        .frame(width: Space.s8 * 14)
        .corePanel(radius: Radius.panel + Space.s1, padding: 0)
        .shadow(color: .black.opacity(0.35), radius: 40, y: 16)
        .scaleEffect(shown || reduce ? 1 : 0.92)
        .opacity(shown ? 1 : 0)
        .animation(.spring(duration: 0.4, bounce: 0.25), value: shown)
        .animation(.spring(duration: 0.25, bounce: 0.2), value: selected)
        .onAppear {
            shown = true
            listen()
        }
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) } }
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
            case 53: cancel()  // Esc
            default: return e
            }
            return nil
        }
    }
}

private struct ChoiceTile: View {
    let choice: ConfirmChoice
    let on: Bool
    let keys: String?
    let run: () -> Void
    var body: some View {
        let hue = choice.destructive ? GlassInk.red : GlassInk.blue
        Button(action: run) {
            HStack(spacing: Space.s2) {
                Image(systemName: choice.symbol).font(.system(size: MacTextSize.body, weight: .semibold))
                    .symbolEffect(.bounce, value: on)
                Text(choice.label).font(.system(size: MacTextSize.body, weight: .semibold))
                if let keys {
                    Text(keys).font(.system(size: MacTextSize.meta, weight: .medium, design: .rounded))
                        .padding(.horizontal, 6).frame(minHeight: 20)
                        .background(.white.opacity(0.14), in: coreShape(5))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                on ? hue.opacity(choice.destructive ? 0.85 : 0.6) : GlassInk.well, in: coreShape(Radius.control + 2)
            )
            .overlay {
                coreShape(Radius.control + 2).strokeBorder(on ? .white.opacity(0.4) : GlassInk.wellEdge, lineWidth: 1)
            }
            .shadow(color: on ? hue.opacity(0.45) : .clear, radius: 10)
            .scaleEffect(on ? 1.03 : 1)
            .contentShape(coreShape(Radius.control + 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
