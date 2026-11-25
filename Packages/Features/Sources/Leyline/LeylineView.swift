import CoreUI
import Projects
import Shell
import SwiftUI

/// The Leyline pane: the hosts as a map or a list with the selected host's panel and the Keys panel, or an opened host. Every
/// action has a key: type to find (⌘K focuses the field), arrows move, Return opens the terminal, ⌘2 files, ⌘3 history,
/// ⌘, access, ⌘M / ⌘L map or list, N adds a host, Esc goes back. The pane's surface follows the
/// Look's transparency and blur.
struct LeylineView: View {
    let model: LeylineModel
    @FocusState private var paneFocus: Bool
    @FocusState private var findFocus: Bool

    var body: some View {
        ZStack {
            if let host = model.open {
                HostView(model: model, host: host).id(host.id).transition(.opacity)
            } else {
                LeylineHome(model: model, findFocus: $findFocus).transition(.opacity)
            }
        }
        // The pane's surface follows the Look (Settings, Appearance, or Leyline's own): transparency and blur, like
        // Connections and Accounts.
        .paneLook(AppLookPrefs.shared("leyline").look)
        .appLookTheme(AppLookPrefs.shared("leyline"))
        .clipShape(coreShape(Radius.cardMac))
        .focusable()
        .focused($paneFocus)
        .focusEffectDisabled()
        .onAppear { paneFocus = true }
        .retakeFocus(after: model.host.shell, pane: "leyline") { paneFocus = true }
        .onKeyPress(phases: .down) { key($0) }
        .task {
            // The Core probes once a minute; the page reads what it stored on the same beat.
            while !Task.isCancelled {
                await model.refreshHealth()
                try? await Task.sleep(for: .seconds(15))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("leyline-pane")
    }

    private func key(_ press: KeyPress) -> KeyPress.Result {
        let cmd = press.modifiers.contains(.command)
        let c = press.characters.lowercased()
        if press.key == .escape {
            if model.openID != nil {
                model.closeHost()
                paneFocus = true
                return .handled
            }
            if model.keysOpen {
                model.keysOpen = false
                return .handled
            }
            if !model.filter.isEmpty {
                model.filter = ""
                return .handled
            }
            return .ignored
        }
        if cmd, let ch = c.first, let tab = HostSection.forKey(ch) {
            guard let id = model.openID ?? model.selected else { return .ignored }
            if model.openID != nil { model.section = tab } else { model.openHost(id, tab) }
            return .handled
        }
        guard model.openID == nil, model.load == .ready else { return .ignored }
        if model.keysOpen {
            // ↑ ↓ move through the keys; ⌘G and ⌘I are the panel's own buttons.
            guard press.key == .upArrow || press.key == .downArrow, !model.keys.isEmpty else { return .ignored }
            let ids = model.keys.map(\.id)
            let at = model.keySelected.flatMap { ids.firstIndex(of: $0) }
            let next = press.key == .upArrow ? max((at ?? ids.count) - 1, 0) : min((at ?? -1) + 1, ids.count - 1)
            model.keySelected = ids[next]
            return .handled
        }
        if cmd {
            switch c {
            case "k":
                findFocus = true
                return .handled
            case "m", "l":
                withAnimation(Motion.out(Motion.ui)) { model.layout = c == "m" ? .map : .list }
                return .handled
            default: return .ignored
            }
        }
        switch press.key {
        case .return:
            guard let id = model.selected else { return .ignored }
            model.openHost(id)
            return .handled
        case .leftArrow: return model.move(dx: -1, dy: 0) ? .handled : .ignored
        case .rightArrow: return model.move(dx: 1, dy: 0) ? .handled : .ignored
        case .upArrow: return model.move(dx: 0, dy: -1) ? .handled : .ignored
        case .downArrow: return model.move(dx: 0, dy: 1) ? .handled : .ignored
        default: break
        }
        guard !findFocus, press.modifiers.subtracting(.shift).isEmpty else { return .ignored }
        if c == "n", model.filter.isEmpty {
            model.newHost()
            return .handled
        }
        if c.count == 1,
            c.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "-._".unicodeScalars.contains($0) }
            )
        {
            model.type(c)
            return .handled
        }
        return .ignored
    }
}

/// The top bar and the hosts (map or list, with the host panel); the Keys panel slides in over the right of them, the map
/// staying usable beside it.
struct LeylineHome: View {
    let model: LeylineModel
    var findFocus: FocusState<Bool>.Binding
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                bar
                hosts.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if model.keysOpen {
                KeysPanel(model: model)
                    .padding(Space.s3)
                    // Slides a few points in from the right edge and fades; a fade only under Reduce Motion.
                    .transition(reduce ? .opacity : .opacity.combined(with: .offset(x: Space.s5)))
            }
        }
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: model.keysOpen)
        .foregroundStyle(GlassInk.primary)
        .coreFont(size: MacTextSize.body)
    }

    private var bar: some View {
        HStack(spacing: Space.s2 + 2) {
            FindField(
                text: Binding(
                    get: { model.filter },
                    set: {
                        model.filter = $0
                        model.filterChanged()
                    }), focus: findFocus
            ) {
                if let id = model.selected { model.openHost(id) }
            }
            if model.load == .ready {
                Text("\(Words.count(model.fleet.count, "host")) · \(model.onlineCount) online")
                    .coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: Space.s3)
            trailing
                // Under the Keys panel: hidden, so no edge of them shows beside it (Esc or the panel's esc closes it).
                .opacity(model.keysOpen ? 0 : 1).allowsHitTesting(!model.keysOpen).accessibilityHidden(model.keysOpen)
        }
        .padding(.horizontal, Space.s5).padding(.top, Space.s3 + 2).padding(.bottom, Space.s3)
    }

    /// Map or list, Keys and Add Host.
    @ViewBuilder private var trailing: some View {
        HStack(spacing: Space.s2 + 2) {
            KeyTabs(
                label: "Map or list",
                tabs: [
                    .init(
                        id: LeylineLayout.map, title: "Map", symbol: "point.3.connected.trianglepath.dotted",
                        key: "⌘M"),
                    .init(id: .list, title: "List", symbol: "list.bullet", key: "⌘L"),
                ],
                selection: Binding(
                    get: { model.layout }, set: { l in withAnimation(Motion.out(Motion.ui)) { model.layout = l } }))
            CoreIconButton(symbol: "key", label: "Keys", selected: model.keysOpen) { model.keysOpen.toggle() }
                .help("Keys")
                .accessibilityIdentifier("leyline-keys-button")
            Button {
                model.newHost()
            } label: {
                Label("Add Host", systemImage: "plus")
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            .environment(\.coreKeycap, "N")
            .disabled(model.readOnly || model.load != .ready)
            .accessibilityIdentifier("leyline-add-host")
        }
    }

    @ViewBuilder private var hosts: some View {
        switch model.load {
        case .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .notConnected:
            centered(
                CoreStateCard(
                    symbol: "wifi.slash", title: "Not connected",
                    line: "Hosts live on your Core. They show up here once this Mac is connected."))
        case .absent:
            centered(
                CoreStateCard(
                    symbol: "point.3.connected.trianglepath.dotted", title: "This Core has no Leyline",
                    line: "Leyline arrives with a Core update. Hosts and keys show up here after it."))
        case .failed(let why):
            centered(
                CoreStateCard(
                    symbol: "exclamationmark.triangle", title: "Hosts did not load", line: why,
                    primary: CoreAction("Try again") { model.resync() }))
        case .ready:
            if model.hosts.isEmpty {
                centered(
                    CoreStateCard(
                        symbol: "server.rack", title: "No hosts yet",
                        line: "Add one with N. Paste a whole ssh command into Host and the rest fills in.",
                        primary: CoreAction("Add Host") { model.newHost() }))
            } else if model.fleet.isEmpty {
                centered(
                    CoreStateCard(
                        symbol: "line.3.horizontal.decrease", title: "No host to show",
                        line: "No host fits “\(LeylineOptions.current.title)”. Change it in Settings, Leyline, Options."
                    ))
            } else {
                ready
            }
        }
    }

    private var ready: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    switch model.layout {
                    case .map:
                        if model.bigMap { GroupsMap(model: model) } else { RoutesMap(model: model) }
                    case .list:
                        if model.shown.isEmpty {
                            Text("No host matches “\(model.filter)”.").foregroundStyle(GlassInk.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            HostList(model: model)
                        }
                    }
                }
                .transition(.opacity)
                if let h = model.selectedHost, !model.keysOpen {
                    HostPeek(model: model, host: h)
                        .padding(.trailing, Space.s5).padding(.bottom, Space.s1)
                        .transition(.opacity)
                }
            }
            .animation(Motion.out(Motion.ui), value: model.layout)
            .animation(Motion.out(Motion.ui), value: model.selected == nil)
            KeyHints(hints: [
                ("↑↓←→", "move"), ("⏎", "terminal"), ("⌘2", "files"), ("⌘3", "history"), ("N", "add host"),
                ("type", "find"),
            ])
        }
    }

    private func centered<V: View>(_ v: V) -> some View {
        v.frame(maxWidth: .infinity, maxHeight: .infinity).padding(Space.s4)
    }
}
