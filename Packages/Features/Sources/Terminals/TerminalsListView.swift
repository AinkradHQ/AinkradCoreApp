import CoreUI
import SwiftUI

/// The Terminals app (E6-3, `screens/08-terminals.html`): the terminals grouped by machine, one row each (Ahmed, 2026-11-21:
/// a list, not cards). This Mac's real shells come first, then the sandboxes. ⌘T opens a terminal at once in the Core sandbox,
/// ⌃⌘T a real shell on this Mac; "New terminal…" (⌥⌘N) opens the sheet. Keyboard: ↑ ↓ move, ⏎ opens, ⌫ or ⌘⌫ closes,
/// D detach, S running command, R rename.
struct TerminalsListView: View {
    @Environment(\.coreAccent) private var paneAccent
    let model: TerminalsModel
    @Bindable private var prefs = TerminalPrefs.shared
    @FocusState private var listFocus: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        // The pane's frame draws the background: Settings, Appearance's Look, or the app's own.
        .paneLook(prefs.look)
        .appLookTheme(prefs.appLook)
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
            AppActionTile(
                title: "New terminal…", symbol: "slider.horizontal.3", key: "⌥⌘N", hue: GlassInk.accent(paneAccent)
            ) {
                model.openNew()
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            if model.host.thisMacRunnerID != nil {
                // ⌃⌘T is bound by the app's File menu (New Terminal on This Mac); the tile shows the key.
                AppActionTile(
                    title: "On This Mac", symbol: "laptopcomputer", key: "⌃⌘T", hue: GlassInk.accent(paneAccent)
                ) {
                    model.newOnThisMac()
                }
            }
            AppActionTile(
                title: "New terminal", symbol: "plus", key: "⌘T", hue: GlassInk.accent(paneAccent), prominent: true
            ) {
                model.quickNew()
            }
            .keyboardShortcut("t", modifiers: .command)
        }
    }

    private func count(_ f: TerminalFilter) -> Int {
        let mac = model.host.thisMacRunnerID
        return model.items.filter { f.matches($0, thisMac: mac) }.count
    }

    @ViewBuilder private var content: some View {
        switch model.load {
        case .failed(let message):
            ConnectionBanner(.error(message), retry: { Task { await model.reload() } }).padding(.horizontal, Space.s3)
            Spacer(minLength: 0)
        case .idle where model.items.isEmpty, .loading where model.items.isEmpty:
            CoreBusyBar().padding(Space.s4)
            Spacer(minLength: 0)
        default:
            if model.shown.isEmpty {
                empty
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.s5) {
                            ForEach(model.groups) { g in section(g) }
                        }
                        .padding(.horizontal, Space.s4).padding(.bottom, Space.s3)
                    }
                    .scrollIndicators(.never)
                    .focusable()
                    .focused($listFocus)
                    .focusEffectDisabled()
                    .onKeyPress(.downArrow) { move(1, proxy) }
                    .onKeyPress(.upArrow) { move(-1, proxy) }
                    .onKeyPress(.return) { act(.open) }
                    .onKeyPress(.delete) { act(.end) }
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

    /// One machine: its picture, what it is, how many, then its rows.
    private func section(_ g: TerminalGroup) -> some View {
        let runner = model.runner(g.id)
        let mac = g.isThisMac
        let title = mac ? "This Mac" : runner?.builtIn == true ? "Core sandbox" : g.name
        let about =
            mac
            ? "A real shell. It can change your files."
            : runner?.builtIn == true ? "A safe room. It cannot see your files." : "Sandbox on this machine."
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                IconTile(
                    mac ? "laptopcomputer" : runner?.builtIn == true ? "diamond" : "server.rack",
                    hue: mac ? GlassInk.amber : GlassInk.accent(paneAccent), size: Space.s8 - Space.s1,
                    bounce: g.items.count)
                Text(title).coreFont(size: MacTextSize.headline, weight: .semibold)
                Text(about).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Text("\(g.items.count)").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            VStack(spacing: Space.s1) {
                ForEach(Array(g.items.enumerated()), id: \.element.id) { i, t in
                    TerminalRow(model: model, item: t, thisMac: mac || t.isReal, index: i).id(t.id)
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: Space.s3) {
            IconTile("terminal", hue: GlassInk.accent(paneAccent), size: 64)
            Text("No terminals yet").coreFont(size: MacTextSize.title, weight: .semibold)
            Text(
                "Open a terminal in a safe sandbox, or a real one on this Mac. They show up here with a live look at what they are doing."
            )
            .foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center).frame(maxWidth: Space.s8 * 13)
            HStack(spacing: Space.s2) {
                if let mac = model.host.thisMacRunnerID {
                    Button {
                        model.openNew(runner: mac)
                    } label: {
                        Label("On this Mac", systemImage: "laptopcomputer")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary))
                }
                Button {
                    model.quickNew()
                } label: {
                    Label("In a sandbox", systemImage: "shield")
                }
                .buttonStyle(CoreButtonStyle(.prominent))
            }
            Text("Tip: press ⌘T any time, or ⌃⌘T for this Mac.").coreFont(size: MacTextSize.meta).foregroundStyle(
                GlassInk.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func move(_ step: Int, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        let rows = model.shown
        guard !rows.isEmpty else { return .ignored }
        let i = rows.firstIndex { $0.id == model.selected } ?? (step > 0 ? -1 : rows.count)
        let next = rows[min(max(i + step, 0), rows.count - 1)].id
        withAnimation(Motion.calm(Motion.out(Motion.ui), reduce)) { model.selected = next }
        proxy.scrollTo(next)
        return .handled
    }

    private func act(_ a: TileAction) -> KeyPress.Result {
        guard let id = model.selected ?? model.shown.first?.id else { return .ignored }
        TileAction.run(a, id, model)
        return .handled
    }

    private var footer: some View {
        HStack(spacing: Space.s4) {
            hint("↑ ↓", "Move")
            hint("⏎", "Open")
            hint("⌘T", "New terminal")
            if model.host.thisMacRunnerID != nil { hint("⌃⌘T", "On This Mac") }
            hint("⌫", "Close")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
    }

    private func hint(_ keys: String, _ what: String) -> some View {
        HStack(spacing: Space.s2) {
            CoreKeycap(keys)
            Text(what).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// What a tile can do, from its hover buttons or the keyboard.
enum TileAction {
    case open, detach, end, signal, rename

    @MainActor static func run(_ a: TileAction, _ id: String, _ model: TerminalsModel) {
        switch a {
        case .open: model.openTerminal(id)
        case .detach: model.sessions[id]?.detach()
        case .end:
            // An ended terminal has nothing to stop: Close just takes it off the list.
            if model.items.first(where: { $0.id == id })?.isEnded ?? true {
                model.dismiss(id)
            } else if let s = model.session(for: id) {
                model.confirmEnd(s)
            }
        case .signal:
            model.openTerminal(id)
            model.shell.toggleActions()
        case .rename:
            model.openTerminal(id, attach: false)
            model.shell.renamingTab = "terminal-\(id)"
        }
    }
}
