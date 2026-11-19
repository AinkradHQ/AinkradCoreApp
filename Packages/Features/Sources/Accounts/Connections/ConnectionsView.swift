import CoreUI
import SwiftUI

/// The Connections pane (CN1, CN6): page tiles and the Connect action in the header, the page, status chips at the foot.
struct ConnectionsView: View {
    let model: ConnectionsModel
    @FocusState private var paneFocus: Bool

    private func arrow(_ step: Int) -> KeyPress.Result {
        withAnimation(.smooth(duration: 0.2)) { model.move(step) }
        return .handled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppHeader {
                AppFilterTile(title: "Connections", count: model.shown.count, on: true, key: "") {}
            } actions: {
                AppActionTile(title: "Connect", symbol: "plus", key: "⌘N", hue: GlassInk.blue, prominent: true) {
                    model.beginAdd()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(model.service == nil)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    AccNotice(notice: model.host.elevationNotice)
                    if model.sample {
                        CoreNotice(
                            symbol: "info.circle", title: "Sample connections",
                            text:
                                "This page shows made-up connections to try things on. Nothing here reaches your Core."
                        )
                    }
                    content
                }
                .coreFont(size: MacTextSize.body)
                .foregroundStyle(GlassInk.primary)
                .padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .focusable()
            .focused($paneFocus)
            .focusEffectDisabled()
            .onAppear { paneFocus = true }
            .retakeFocus(after: model.host.shell, pane: "connections") { paneFocus = true }
            .onKeyPress(.downArrow) { arrow(1) }
            .coreSideKeys { arrow($0) }
            .onKeyPress(.upArrow) { arrow(-1) }
            .onKeyPress(.return) { model.key("↩") ? .handled : .ignored }
            .onKeyPress(.delete) { model.key("⌫") ? .handled : .ignored }
            .onKeyPress(.escape) {
                guard model.cursor != nil else { return .ignored }
                model.cursor = nil
                return .handled
            }
            .onKeyPress(characters: .letters) { model.key($0.characters.lowercased()) ? .handled : .ignored }
        }
        .paneLook(AccountsPrefs.shared.look)
        .clipShape(coreShape(Radius.cardMac))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connections-pane")
    }

    @ViewBuilder private var content: some View {
        if model.service == nil {
            AccStateCard(
                symbol: "link", title: "Not connected to a Core",
                text: "Connect this Mac to your Core first. Then you sign in to GitHub, Jira and others here.")
        } else {
            switch model.load {
            case .loading: AccSkeleton()
            case .ready:
                ConnListPage(model: model).transition(.opacity)
            default:
                AccStateCard(
                    symbol: "exclamationmark.triangle", title: "Couldn't load connections",
                    text: "Your Core didn't answer. Nothing was changed.", tone: .fail
                ) {
                    AppActionTile(title: "Try again", symbol: "arrow.clockwise", key: "R", hue: GlassInk.blue) {
                        Task { await model.reload() }
                    }
                }
            }
        }
    }
}

/// The list (mockup 10): a row per connection, then the services not connected yet; or the empty page with the tiles.
struct ConnListPage: View {
    let model: ConnectionsModel

    var body: some View {
        if model.shown.isEmpty { empty } else { list }
    }

    private var list: some View {
        let free = model.kinds.filter { k in !model.shown.contains { $0.kind == k.id } }
        return VStack(alignment: .leading, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: Space.s1 / 2) {
                Text("Connections").coreFont(size: MacTextSize.large, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                Text("Services your assistant can look at. You choose what it may do.")
                    .foregroundStyle(GlassInk.secondary)
            }
            .padding(.bottom, Space.s2)
            ForEach(model.shown) { c in ConnRow(model: model, item: c) }
            if !free.isEmpty {
                Text("Connect another").coreFont(size: MacTextSize.meta, weight: .semibold)
                    .foregroundStyle(GlassInk.secondary).padding(.top, Space.s5).padding(.bottom, Space.s1)
                HStack(spacing: Space.s2) {
                    ForEach(free) { k in ConnAddTile(kind: k) { model.beginAdd(kind: k.id) } }
                }
            }
        }
    }

    /// Ainkrad signs in for you, so there is nothing to set up first.
    private var empty: some View {
        VStack(spacing: Space.s2) {
            IconTile("link", hue: GlassInk.blue, size: 72, bounce: false).connFloat().padding(.top, Space.s8)
            Text("Connect your first service").coreFont(size: MacTextSize.title, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            Text("Let your assistant read your code, tickets and chats. It never changes anything unless you say so.")
                .foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: Space.s8 * 13).padding(.bottom, Space.s3)
            ConnTiles(kinds: model.kinds) { model.beginAdd(kind: $0) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("connections-empty")
    }
}

/// A service not connected yet, as a quiet tile under the list.
struct ConnAddTile: View {
    let kind: ConnKind
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                ConnLogo(kind: kind.id)
                VStack(alignment: .leading, spacing: 0) {
                    Text(kind.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                    Text(kind.say).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s3 - 2)
            .frame(maxWidth: .infinity)
            .background(GlassInk.well, in: coreShape(Radius.cardMac))
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(CoreQuietPressStyle(radius: Radius.cardMac))
        .accessibilityLabel("Connect \(kind.name)")
    }
}

/// One connection: logo, service and who, what AI may do and how much it reaches, the state, and More.
struct ConnRow: View {
    let model: ConnectionsModel
    let item: ConnItem
    @State private var menuOpen = false
    @State private var moreHover = false
    @Environment(\.corePalette) private var palette

    private var kind: ConnKind? { model.kind(item.kind) }
    private var oauth: Bool { item.authMethod == "oauth" }

    /// The four of the mockup first, then the rest of what a connection can do, Disconnect last.
    private var menuItems: [CoreDropdownItem] {
        let noun = kind?.resource ?? "places"
        var out = [
            CoreDropdownItem("What AI may do…", symbol: "eye") { model.beginEdit(item, at: .allow) },
            CoreDropdownItem("Choose \(noun)…", symbol: "folder") { model.beginEdit(item, at: .choose) },
            CoreDropdownItem("Sign in again", symbol: "arrow.clockwise", enabled: oauth) { model.beginAgain(item) },
            CoreDropdownItem("Test connection", symbol: "checkmark.seal") {
                Task {
                    await model.test(item)
                    if let said = model.tested[item.id] { model.host.shell.showToast(said) }
                }
            },
            CoreDropdownItem("Rename…", symbol: "pencil") { ConnDialogs.openRename(model, item) },
            item.isDefault
                ? CoreDropdownItem("Clear default", symbol: "star.slash") { Task { await model.clearDefault(item) } }
                : CoreDropdownItem("Use by default", symbol: "star") { Task { await model.makeDefault(item) } },
        ]
        if !oauth { out.append(CoreDropdownItem("Replace token…", symbol: "key") { ConnDialogs.openReplace(model, item) }) }
        if !model.host.shell.settings.hidden.contains("audit") {
            out.append(CoreDropdownItem("History", symbol: "clock.arrow.circlepath") { model.openHistory(item) })
        }
        out.append(CoreDropdownItem("Disconnect", symbol: "trash", destructive: true) { model.disconnectWithUndo(item) })
        return out
    }

    var body: some View {
        let (label, tone, symbol) = ConnLook.chip(item)
        let on = model.cursor == item.id
        HStack(spacing: Space.s4) {
            ConnLogo(kind: item.kind)
            VStack(alignment: .leading, spacing: 0) {
                Text(kind?.name ?? item.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                Text(item.identity).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(ConnAccess.lead(kind, allowed: item.allowed)).coreFont(size: MacTextSize.meta + 1, weight: .semibold)
                Text(ConnAccess.scope(kind, only: item.only)).coreFont(size: MacTextSize.meta + 1)
                    .foregroundStyle(GlassInk.secondary)
            }
            .lineLimit(1).frame(width: 228, alignment: .leading)
            StateBadge(label, tone: tone, symbol: symbol).frame(width: 132, alignment: .leading)
                .help(item.reason ?? "")
            Group {
                if item.signInNeeded && oauth {
                    Button("Sign in") { model.beginAgain(item) }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            }
            .frame(width: 68, alignment: .trailing)
            CoreDropdown(items: menuItems, isPresented: $menuOpen) {
                Image(systemName: "ellipsis").coreFont(size: MacTextSize.body, weight: .semibold)
                    .foregroundStyle(GlassInk.primary)
                    .frame(width: MacSize.controlMd, height: MacSize.controlSm)
                    .background(moreHover || menuOpen ? GlassInk.wellHover : Color.clear, in: coreShape(Radius.chip))
                    .contentShape(coreShape(Radius.chip))
                    .onHover { moreHover = $0 }
                    .animation(Motion.out(Motion.hover), value: moreHover)
            }
            .help("More")
            .accessibilityLabel("More actions for \(kind?.name ?? item.name)")
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        .frame(minHeight: 68)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .overlay { if on { coreShape(Radius.cardMac).fill(palette.navActive).allowsHitTesting(false) } }
        .contextMenu {
            ForEach(menuItems) { i in
                Button(i.title, role: i.destructive ? .destructive : nil) { i.run() }.disabled(!i.enabled)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(kind?.name ?? item.name), \(item.identity), \(label)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
