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
            if model.keyForm != nil {
                model.closeKeyForm()
                return .handled
            }
            if model.keysOpen {
                model.closeKeys()
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
            // ↑ ↓ open the next key; ⌘G, ⌘I and ⌘C are the panel's own.
            guard press.key == .upArrow || press.key == .downArrow, model.keyForm == nil else { return .ignored }
            model.moveKey(down: press.key == .downArrow)
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
    @Environment(\.coreAccent) private var paneAccent

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                header
                hosts.frame(maxWidth: .infinity, maxHeight: .infinity)
                LeylineFooter(model: model)
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

    /// The app header every pane uses: Map and List as the page tiles at the left; find, Keys and Add Host at the right.
    private var header: some View {
        AppHeader {
            AppFilterTile(title: "Map", count: -1, on: model.layout == .map, key: "⌘M") { show(.map) }
                .accessibilityIdentifier("tab-Map")
            AppFilterTile(title: "List", count: -1, on: model.layout == .list, key: "⌘L") { show(.list) }
                .accessibilityIdentifier("tab-List")
        } actions: {
            HStack(spacing: Space.s2) {
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
                AppActionTile(title: "Keys", symbol: "key", key: "", hue: GlassInk.accent(paneAccent)) {
                    if model.keysOpen { model.closeKeys() } else { model.keysOpen = true }
                }
                .accessibilityIdentifier("leyline-keys-button")
                AppActionTile(
                    title: "Add Host", symbol: "plus", key: "N", hue: GlassInk.accent(paneAccent), prominent: true
                ) {
                    model.newHost()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(model.readOnly || model.load != .ready)
                .accessibilityIdentifier("leyline-add-host")
            }
            // Under the Keys panel: hidden, so no edge of them shows beside it (Esc or the panel's esc closes it).
            .opacity(model.keysOpen ? 0 : 1).allowsHitTesting(!model.keysOpen).accessibilityHidden(model.keysOpen)
        }
    }

    private func show(_ layout: LeylineLayout) {
        withAnimation(Motion.out(Motion.ui)) { model.layout = layout }
    }

    @ViewBuilder private var hosts: some View {
        switch model.load {
        case .loading:
            page(LeylineSkeleton())
        case .notConnected:
            page(
                LeylineStateCard(
                    symbol: "wifi.slash", title: "Not connected",
                    text: "Hosts live on your Core. They show up here once this Mac is connected."))
        case .absent:
            page(
                LeylineStateCard(
                    symbol: "point.3.connected.trianglepath.dotted", title: "This Core has no Leyline",
                    text: "Leyline arrives with a Core update. Hosts and keys show up here after it."))
        case .failed(let why):
            page(
                LeylineStateCard(
                    symbol: "exclamationmark.triangle", title: "Hosts did not load",
                    text: "The Core answered with an error. \(why) Nothing was changed.", tone: .fail
                ) {
                    AppActionTile(
                        title: "Try again", symbol: "arrow.clockwise", key: "", hue: GlassInk.accent(paneAccent)
                    ) {
                        model.resync()
                    }
                })
        case .ready:
            if model.hosts.isEmpty {
                page(
                    LeylineStateCard(
                        symbol: "server.rack", title: "No hosts yet",
                        text: "Add one with N. Paste a whole ssh command into Host and the rest fills in."
                    ) {
                        AppActionTile(
                            title: "Add Host", symbol: "plus", key: "N", hue: GlassInk.accent(paneAccent),
                            prominent: true
                        ) {
                            model.newHost()
                        }
                        .disabled(model.readOnly)
                    })
            } else if model.fleet.isEmpty {
                page(
                    LeylineStateCard(
                        symbol: "line.3.horizontal.decrease", title: "No host to show",
                        text: "No host fits “\(LeylineOptions.current.title)”. Change it in Settings, Leyline, Options."
                    ))
            } else {
                ready
            }
        }
    }

    private var ready: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                switch model.layout {
                case .map:
                    if model.bigMap { GroupsMap(model: model) } else { RoutesMap(model: model) }
                case .list:
                    if model.shown.isEmpty {
                        page(
                            LeylineStateCard(
                                symbol: "magnifyingglass", title: "No host matches “\(model.filter)”",
                                text: "Try another name or address. Esc clears the find field."))
                    } else {
                        HostList(model: model)
                    }
                }
            }
            .transition(.opacity)
            if let h = model.selectedHost, !model.keysOpen {
                HostPeek(model: model, host: h)
                    .padding(.trailing, Space.s4).padding(.bottom, Space.s1)
                    .transition(.opacity)
            }
        }
        .animation(Motion.out(Motion.ui), value: model.layout)
        .animation(Motion.out(Motion.ui), value: model.selected == nil)
    }

    /// A state in place of the hosts: at the top of the page, inside its margins, like Accounts and Connections.
    private func page<V: View>(_ v: V) -> some View {
        v.padding(.horizontal, Space.s4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
