import CoreUI
import SwiftUI

/// The Terminals app: its own surface (Settings, Terminal, App surface), the filter, a mini-terminal tile per terminal,
/// and the counts. Keyboard: ⌘1 ⌘2 ⌘3 filter, arrows move, ↩ open, D detach, E end, S signal, R rename, ⌥⌘N new,
/// ⌥⌘P appearance. The Core keeps no output, so a tile shows the shell, not its screen.
struct TerminalsListView: View {
    let model: TerminalsModel
    @Bindable private var prefs = TerminalPrefs.shared
    @FocusState private var listFocus: Bool
    @State private var appearance = false

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        .background { AppSurface(prefs: prefs) }
        .onAppear { listFocus = true }
    }

    private var header: some View {
        HStack(spacing: Space.s2) {
            ForEach(Array(TerminalFilter.allCases.enumerated()), id: \.element) { i, f in
                FilterTile(title: f.rawValue, count: count(f), on: model.filter == f, key: "⌘\(i + 1)") {
                    model.filter = f
                }
                .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
            Spacer(minLength: Space.s2)
            ActionTile(title: "Appearance", symbol: "paintpalette", key: "⌥⌘P", hue: GlassInk.violet) {
                appearance.toggle()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .popover(isPresented: $appearance, arrowEdge: .bottom) { AppearancePopover(prefs: prefs) }
            ActionTile(title: "New", symbol: "plus", key: "⌥⌘N", hue: GlassInk.blue, prominent: true) {
                model.quickNew()
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
        }
        .padding(.horizontal, Space.s4).padding(.top, Space.s2).padding(.bottom, Space.s3)
    }

    private func count(_ f: TerminalFilter) -> Int {
        switch f {
        case .all: model.items.count
        case .running: model.items.filter { !$0.isEnded }.count
        case .ended: model.items.filter(\.isEnded).count
        }
    }

    @ViewBuilder private var content: some View {
        switch model.load {
        case .failed(let message):
            ConnectionBanner(.error(message), retry: { Task { await model.reload() } }).padding(.horizontal, Space.s3)
            Spacer(minLength: 0)
        case .idle where model.items.isEmpty, .loading where model.items.isEmpty:
            BusyBar().padding(Space.s4)
            Spacer(minLength: 0)
        default:
            if model.shown.isEmpty {
                VStack(spacing: Space.s3) {
                    IconTile("terminal", hue: GlassInk.slate, size: 64)
                    Text("No terminals here").font(.system(size: MacTextSize.title, weight: .semibold))
                    Text("Open a shell on one of your runners.").foregroundStyle(GlassInk.secondary)
                    Button("New terminal") { model.quickNew() }.buttonStyle(CoreButtonStyle(.prominent))
                        .coreShortcut(.primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .contain)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: Space.s8 * 10), spacing: Space.s3, alignment: .top)],
                            spacing: Space.s3
                        ) {
                            ForEach(Array(model.shown.enumerated()), id: \.element.id) { i, t in
                                TerminalTile(model: model, item: t, index: i).id(t.id)
                            }
                        }
                        .padding(.horizontal, Space.s4).padding(.bottom, Space.s3)
                    }
                    .scrollIndicators(.never)
                    .focusable()
                    .focused($listFocus)
                    .focusEffectDisabled()
                    .onKeyPress(.downArrow) { move(1, proxy) }
                    .onKeyPress(.upArrow) { move(-1, proxy) }
                    .onKeyPress(.rightArrow) { move(1, proxy) }
                    .onKeyPress(.leftArrow) { move(-1, proxy) }
                    .onKeyPress(.return) { act(.open) }
                    .onKeyPress(characters: .letters) { press in
                        switch press.characters.lowercased() {
                        case "d": act(.detach)
                        case "e": act(.end)
                        case "s": act(.signal)
                        case "r": act(.rename)
                        default: .ignored
                        }
                    }
                    .accessibilityLabel("Terminals")
                }
            }
        }
    }

    private func move(_ step: Int, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        let rows = model.shown
        guard !rows.isEmpty else { return .ignored }
        let i = rows.firstIndex { $0.id == model.selected } ?? (step > 0 ? -1 : rows.count)
        let next = rows[min(max(i + step, 0), rows.count - 1)].id
        withAnimation(.spring(duration: 0.25)) { model.selected = next }
        proxy.scrollTo(next)
        return .handled
    }

    private func act(_ a: TileAction) -> KeyPress.Result {
        guard let id = model.selected ?? model.shown.first?.id else { return .ignored }
        TileAction.run(a, id, model)
        return .handled
    }

    private var footer: some View {
        let running = model.items.filter { !$0.isEnded }.count
        let ended = model.items.count - running
        return HStack(spacing: Space.s2) {
            stat("play.fill", "\(running) running", GlassInk.green)
            if ended > 0 { stat("stop.fill", "\(ended) ended", GlassInk.slate) }
            ForEach(model.runners.filter { model.onRunner($0.id) > 0 }) { r in
                stat("server.rack", "\(r.name) · \(model.onRunner(r.id))", RunnerHue.of(r.name))
            }
            Spacer(minLength: 0)
            Text("↩ open · D detach · E end · S signal · R rename").font(.system(size: MacTextSize.meta))
                .foregroundStyle(GlassInk.secondary)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        .help("Terminals this device opened. The Core keeps no output, so a tile shows the shell, not its screen.")
    }

    private func stat(_ symbol: String, _ text: String, _ hue: Color) -> some View {
        HStack(spacing: Space.s1) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(hue)
            Text(text).monospacedDigit()
        }
        .font(.system(size: MacTextSize.meta, weight: .medium))
        .padding(.horizontal, Space.s2).frame(height: MacSize.controlSm + 2)
        .background(GlassInk.well, in: coreShape(Radius.chip))
    }
}

/// What a tile can do, from its hover buttons or the keyboard.
enum TileAction {
    case open, detach, end, signal, rename

    @MainActor static func run(_ a: TileAction, _ id: String, _ model: TerminalsModel) {
        switch a {
        case .open: model.openTerminal(id)
        case .detach: model.sessions[id]?.detach()
        case .end: if let s = model.session(for: id) { model.confirmEnd(s) }
        case .signal:
            model.openTerminal(id)
            model.shell.toggleActions()
        case .rename:
            model.openTerminal(id, attach: false)
            model.shell.renamingTab = "terminal-\(id)"
        }
    }
}

/// A runner's own colour, so tiles from different machines tell apart at a glance.
enum RunnerHue {
    static func of(_ name: String) -> Color {
        let hues = [
            GlassInk.blue, GlassInk.violet, GlassInk.green, GlassInk.orange, Color(red: 0.3, green: 0.82, blue: 0.9),
        ]
        return hues[abs(name.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % hues.count]
    }
}

/// The Terminals app's surface, from Settings: glass clear or frosted, the theme's colour, or solid.
private struct AppSurface: View {
    let prefs: TerminalPrefs
    var body: some View {
        let shape = coreShape(Radius.pane)
        Group {
            switch prefs.surface {
            case .clear: shape.fill(.black.opacity(prefs.surfaceOpacity * 0.6))
            case .frosted:
                shape.fill(.ultraThinMaterial).overlay { shape.fill(.black.opacity(prefs.surfaceOpacity * 0.6)) }
            case .theme: shape.fill(Color(nsColor: prefs.theme.background).opacity(0.4 + prefs.surfaceOpacity * 0.6))
            case .solid: shape.fill(Color(red: 0.05, green: 0.06, blue: 0.09).opacity(0.5 + prefs.surfaceOpacity * 0.5))
            }
        }
        .environment(\.colorScheme, .dark)
        .padding(-Space.s2)
        .animation(.easeOut(duration: 0.25), value: prefs.surface)
        .animation(.easeOut(duration: 0.25), value: prefs.surfaceOpacity)
    }
}

/// A filter as a glass tile with its count and key; the lit one glides.
private struct FilterTile: View {
    let title: String
    let count: Int
    let on: Bool
    let key: String
    let pick: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: pick) {
            HStack(spacing: Space.s2) {
                Text(title).font(.system(size: MacTextSize.body, weight: on ? .semibold : .regular))
                Text("\(count)").font(.system(size: MacTextSize.meta, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 6).frame(minHeight: 18)
                    .background(.white.opacity(on ? 0.22 : 0.1), in: coreShape(5))
                    .contentTransition(.numericText())
                if hovering || on {
                    Text(key).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(
                        GlassInk.secondary)
                }
            }
            .foregroundStyle(on ? GlassInk.primary : GlassInk.secondary)
            .padding(.horizontal, Space.s3).frame(height: MacSize.controlMd + 4)
            .background(
                on ? .white.opacity(0.16) : hovering ? .white.opacity(0.07) : .clear, in: coreShape(Radius.control)
            )
            .overlay { if on { coreShape(Radius.control).strokeBorder(.white.opacity(0.25), lineWidth: 1) } }
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: on)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A header action: an icon that bounces on hover, a word, and its key.
private struct ActionTile: View {
    let title: String
    let symbol: String
    let key: String
    let hue: Color
    var prominent = false
    let run: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: run) {
            HStack(spacing: Space.s2) {
                Image(systemName: symbol).font(.system(size: MacTextSize.body, weight: .semibold))
                    .symbolEffect(.bounce, value: hovering)
                Text(title).font(.system(size: MacTextSize.body, weight: .semibold))
                Text(key).font(.system(size: 10, weight: .medium, design: .rounded))
                    .padding(.horizontal, 5).frame(minHeight: 16).background(.white.opacity(0.16), in: coreShape(4))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Space.s3).frame(height: MacSize.controlMd + 4)
            .background(
                prominent ? hue.opacity(hovering ? 0.95 : 0.8) : hovering ? hue.opacity(0.28) : GlassInk.well,
                in: coreShape(Radius.control)
            )
            .overlay { coreShape(Radius.control).strokeBorder(.white.opacity(prominent ? 0.3 : 0.15), lineWidth: 1) }
            .shadow(color: hue.opacity(hovering ? 0.5 : 0), radius: 10)
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.04 : 1)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25, bounce: 0.3), value: hovering)
    }
}
