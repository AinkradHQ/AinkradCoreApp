import AppKit
import CoreUI
import SwiftUI

/// The route Add Host builds as you go: the Core, the jump host when one is chosen, and the server as `user@host:port`.
/// From Sign in on, the last link carries a key (or a lock: the password). On Check the links carry the three checks: a
/// wave runs along while the Core reaches out, the link lights when it answers, the key turns green once signed in, and the
/// server takes a tick when its host key is trusted. Done: the server settles in place, on the map. Reduce Motion: the
/// wave rests and nothing moves; only colour and opacity change.
struct RouteBuild: View {
    let model: LeylineModel
    let flow: AddHostFlow
    @State private var settled = true
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.corePalette) private var palette

    private var jumpName: String? { flow.jump.flatMap { model.hostItem($0)?.name } }
    private var server: String {
        flow.host.isEmpty ? "your server" : "\(flow.user.isEmpty ? "root" : flow.user)@\(flow.host):\(flow.port)"
    }

    /// How the links stand.
    private var link: RouteLink.State {
        switch flow.reach {
        case .running: .running
        case .done: .lit
        case .failed: .broken
        default: .idle
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            stop(caption: "Your Core") { CoreEmblemTile(size: 40) }
            if let jumpName {
                RouteLink(state: link)
                stop(caption: jumpName) { HostTile(symbol: "checkmark.shield", size: 40) }
            }
            RouteLink(state: link, glyph: glyph)
            stop(caption: server, mono: true) {
                HostTile(symbol: "cpu", size: 40)
                    .overlay(alignment: .bottomTrailing) { badge }
                    .opacity(flow.reach.isFailed ? 0.5 : 1)
                    .scaleEffect(settled || reduce ? 1 : 1.08)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: flow)
        .onChange(of: flow.finished) { _, done in
            guard done, !reduce else { return }
            // The server settles into place: up a touch, then home on an ease-out (rare, once per host).
            settled = false
            withAnimation(Motion.out(Motion.move)) { settled = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Route: your Core" + (jumpName.map { ", through \($0)" } ?? "") + ", to \(server)")
    }

    private func stop<T: View>(caption: String, mono: Bool = false, @ViewBuilder tile: () -> T) -> some View {
        VStack(spacing: Space.s1 + 2) {
            tile()
            Text(caption).coreFont(size: MacTextSize.meta, design: mono ? .monospaced : .default)
                .foregroundStyle(GlassInk.secondary).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: Space.s8 * 6)
                .contentTransition(.opacity)
        }
        .frame(minWidth: Space.s8 * 3)
    }

    /// The key on the last link, from Sign in on: green once signed in, red when the key failed.
    private var glyph: RouteLink.Glyph? {
        guard flow.step >= .signIn else { return nil }
        let symbol = flow.key == .none ? "lock" : "key"
        switch flow.signIn {
        case .done: return .init(symbol: symbol, tint: palette.success)
        case .failed: return .init(symbol: symbol, tint: palette.error)
        default: return .init(symbol: symbol, tint: flow.step == .signIn ? palette.primary : GlassInk.secondary)
        }
    }

    @ViewBuilder private var badge: some View {
        if flow.finished {
            mark("checkmark", palette.success)
        } else if case .asks = flow.hostKey {
            mark("questionmark", palette.warning)
        }
    }

    private func mark(_ symbol: String, _ fill: Color) -> some View {
        Image(systemName: symbol).coreFont(size: 9, weight: .bold).foregroundStyle(.white)
            .frame(width: Space.s4, height: Space.s4).background(fill, in: coreShape(Radius.chip - 2))
            .offset(x: Space.s1, y: Space.s1)  // grid: ok a badge sits over the tile's corner
            .transition(.opacity)
    }
}

extension AddHostFlow.Mark {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// A link of the route: small squares in a row. Idle: dim. Running: a wave runs from the Core outward (resting half lit
/// under Reduce Motion). Lit: all on. Broken: the far half dims. A glyph (the key) can sit in its middle.
struct RouteLink: View {
    enum State: Equatable { case idle, running, lit, broken }
    struct Glyph: Equatable {
        let symbol: String
        let tint: Color
    }
    let state: State
    var glyph: Glyph?
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.corePalette) private var palette
    private let count = 8

    var body: some View {
        TimelineView(.animation(paused: reduce || state != .running)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: Space.s1) {
                ForEach(0..<count, id: \.self) { i in
                    if let glyph, i == count / 2 {
                        Image(systemName: glyph.symbol).coreFont(size: MacTextSize.meta, weight: .semibold)
                            .foregroundStyle(glyph.tint).frame(width: Space.s4, height: Space.s4)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    coreShape(1.5).fill(fill(i, t)).frame(width: 5, height: 5)
                }
            }
            .frame(height: 40)
        }
        .accessibilityHidden(true)
    }

    private func fill(_ i: Int, _ t: Double) -> Color {
        switch state {
        case .idle: return GlassInk.track
        case .lit: return palette.primary
        case .broken: return i < count / 2 ? palette.primary.opacity(0.6) : palette.error.opacity(0.6)
        case .running:
            if reduce { return palette.primary.opacity(i < count / 2 ? 0.9 : 0.3) }
            // One wave every 1.2 s, travelling outward; a lit square fades back over the next few.
            let p = (t / 1.2).truncatingRemainder(dividingBy: 1) * Double(count + 3) - Double(i)
            return palette.primary.opacity(p >= 0 && p < 3 ? 1 - p / 3 * 0.7 : 0.3)
        }
    }
}

/// The key choices as one tab stop: ↑ ↓ pick, Space confirms, ⌘I imports, ⌘V pastes a key from the clipboard. The picked
/// row is lit; the list shows it has focus with a brighter edge, not a ring.
struct KeyList: View {
    let wizard: AddHostWizard
    @FocusState private var focused: Bool
    @Environment(\.corePalette) private var palette

    private var model: LeylineModel { wizard.model }
    private var f: AddHostFlow { wizard.f }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                CoreFieldLabel("Key · if it needs one")
                Spacer(minLength: Space.s2)
                Text("↑ ↓ to choose").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .opacity(focused ? 1 : 0)
            }
            VStack(spacing: Space.s1 + 2) {
                KeyOption(
                    symbol: "lock", title: "No key",
                    line: model.previewGaps ? "Password only" : "Type the password in the terminal",
                    on: f.key == .none
                ) { pick(.none) }
                ForEach(model.keys) { k in
                    KeyOption(
                        symbol: "key", title: k.name,
                        line: "\(k.typeWord) · used on \(Words.count(model.usedBy(k).count, "host"))",
                        on: f.key == .saved(k.id)
                    ) { pick(.saved(k.id)) }
                }
                KeyOption(
                    symbol: "square.and.arrow.down", title: "Import a key", line: "From a file or pasted text",
                    on: f.key == .importing, keycap: "⌘I"
                ) { pick(.importing) }
            }
            .coreFocusRing(CoreKeyboardFocus.own(focused), radius: Radius.cardMac, palette: palette)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { if f.focus == .keys { focused = true } }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.space) { .handled }  // the row under the arrows is already the pick
        .onKeyPress(phases: .down) { press in
            guard press.modifiers == .command, press.characters == "v" else { return .ignored }
            return paste() ? .handled : .ignored
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Key")
        .accessibilityIdentifier("add-host-keys")
    }

    private func pick(_ c: AddHostFlow.KeyChoice) {
        wizard.set { $0.key = c }
        focused = true
    }

    private func move(_ step: Int) -> KeyPress.Result {
        wizard.set { $0.moveKey(step, keyIDs: model.keys.map(\.id)) }
        return .handled
    }

    /// ⌘V with a private key on the clipboard: it becomes the imported key.
    private func paste() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string), text.contains("PRIVATE KEY") else {
            return false
        }
        wizard.readKey("Pasted key", text)
        return true
    }
}
