import CoreUI
import SwiftUI

/// The Terminals app: its own surface (Settings, Terminal, App surface), the filter, a mini-terminal tile per terminal,
/// and the counts. Keyboard: ⌘1 ⌘2 ⌘3 filter, arrows move, ↩ open, D detach, E end, S signal, R rename, ⌥⌘N new.
/// The Core keeps no output, so a tile shows the shell, not its screen.
struct TerminalsListView: View {
    let model: TerminalsModel
    @Bindable private var prefs = TerminalPrefs.shared
    @FocusState private var listFocus: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        // The pane's frame draws the background: Settings, Appearance's Look, or the app's own.
        .paneLook(prefs.look)
        .clipShape(coreShape(Radius.cardMac))
        .onAppear { listFocus = true }
    }

    private var header: some View {
        AppHeader {
            ForEach(Array(TerminalFilter.allCases.enumerated()), id: \.element) { i, f in
                AppFilterTile(title: f.rawValue, count: count(f), on: model.filter == f, key: "⌘\(i + 1)") {
                    model.filter = f
                }
                .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
        } actions: {
            AppActionTile(title: "New", symbol: "plus", key: "⌥⌘N", hue: GlassInk.blue, prominent: true) {
                model.quickNew()
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
        }
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
                .foregroundStyle(GlassInk.secondary).lineLimit(1).truncationMode(.tail).layoutPriority(-1)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        .help("Terminals this device opened. The Core keeps no output, so a tile shows the shell, not its screen.")
    }

    private func stat(_ symbol: String, _ text: String, _ hue: Color) -> some View { AppStatChip(symbol, text, hue) }
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
