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
                AppFilterTile(title: "Connections", count: model.items.count, on: true, key: "") {}
            } actions: {
                AppActionTile(title: "Connect", symbol: "plus", key: "⌘N", hue: GlassInk.blue, prominent: true) {
                    ConnDialogs.openConnect(model, kind: nil)
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
            .retakeFocus(after: model.host.shell) { paneFocus = true }
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
            if !model.items.isEmpty {
                HStack(spacing: Space.s2) {
                    AppStatChip("checkmark.seal.fill", "\(model.connected) connected", GlassInk.green)
                    if model.needLook > 0 {
                        AppStatChip("exclamationmark.triangle.fill", "\(model.needLook) need a look", GlassInk.orange)
                    }
                    Spacer(minLength: 0)
                    Text(
                        model.cursor == nil
                            ? "↑↓ move · ⌘N connect"
                            : "↩ who can use it · T test · R rename · D default · ⌫ disconnect"
                    ).coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary)
                }
                .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
            }
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

/// CN1: one section per kind with its connections as cards, or the empty state.
struct ConnListPage: View {
    let model: ConnectionsModel
    @State private var missing: [ConnKind] = []
    private let columns = [GridItem(.adaptive(minimum: Space.s8 * 11), spacing: Space.s3, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            AccHeader(
                title: "Connections",
                detail: "Services Core signs in to for you, so your agents can read issues and code.",
                symbol: "link"
            ) {
                if !model.items.isEmpty {
                    HStack(spacing: Space.s1) {
                        ForEach(ConnFilter.allCases, id: \.self) { f in
                            AppFilterTile(
                                title: f.rawValue, count: model.items.filter { f.matches($0) }.count,
                                on: model.filter == f, key: ""
                            ) { withAnimation(.smooth(duration: 0.3)) { model.filter = f } }
                        }
                    }
                }
            }
            if model.items.isEmpty {
                empty
            } else {
                ForEach(model.liveKinds) { k in
                    VStack(alignment: .leading, spacing: Space.s3) {
                        HStack(spacing: Space.s3) {
                            ConnTile(kind: k.id)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(k.name).coreFont(size: MacTextSize.headline, weight: .semibold)
                                let n = model.items.filter { $0.kind == k.id }.count
                                Text("\(n) connection\(n == 1 ? "" : "s")").coreFont(size: MacTextSize.meta)
                                    .foregroundStyle(GlassInk.secondary)
                            }
                            Spacer()
                            AccLink(
                                title: "App registration", symbol: "gearshape",
                                help: "The \(k.name) app Ainkrad signs in with. Admins only."
                            ) { ConnDialogs.openApp(model, k) }
                            AccLink(title: "Connect another", symbol: "plus") {
                                ConnDialogs.openConnect(model, kind: k.id)
                            }
                        }
                        LazyVGrid(columns: columns, alignment: .leading, spacing: Space.s3) {
                            ForEach(model.items(of: k.id)) { c in ConnCard(model: model, item: c) }
                        }
                    }
                }
            }
        }
    }

    /// Step 1 only when an app is missing: set the sign-in up once. Then connect.
    private var empty: some View {
        AccStateCard(
            symbol: "link", title: "Nothing connected yet",
            text:
                "Sign in to GitHub or Jira once, here. Core keeps the sign-in safe and lets your agents read issues and code. They can't change anything until you allow it."
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                if !missing.isEmpty {
                    emptyStep(
                        1, "Set up sign-in once",
                        "\(missing.map(\.name).joined(separator: " and ")) need\(missing.count == 1 ? "s" : "") an app registered with your Core before anyone can sign in."
                    ) {
                        ForEach(missing) { k in
                            AppActionTile(
                                title: "Set up \(k.name)", symbol: "gearshape", key: "", hue: GlassInk.blue,
                                prominent: true
                            ) { ConnDialogs.openApp(model, k) }
                        }
                    }
                }
                emptyStep(
                    missing.isEmpty ? 1 : 2, "Connect",
                    "Sign in on the service's own website. Core never asks for a password."
                ) {
                    ForEach(model.liveKinds) { k in
                        AppActionTile(
                            title: "Connect \(k.name)", symbol: ConnLook.symbol(k.id), key: "", hue: GlassInk.blue,
                            prominent: missing.isEmpty
                        ) { ConnDialogs.openConnect(model, kind: k.id) }
                        .disabled(missing.contains { $0.id == k.id })
                    }
                }
            }
            .frame(maxWidth: Space.s8 * 14, alignment: .leading)
        }
        .task(id: model.liveKinds.map(\.id)) { await findMissing() }
    }

    private func emptyStep<C: View>(_ n: Int, _ title: String, _ line: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "\(n).square.fill").font(.system(size: 22, weight: .semibold))
                .foregroundStyle(GlassInk.blueInk).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(title).coreFont(size: MacTextSize.headline, weight: .semibold)
                Text(line).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.s2) { c() }
            }
        }
    }

    /// The kinds whose app registration the Core does not have yet. A device that may not read it learns nothing here and
    /// sees only Connect.
    private func findMissing() async {
        var out: [ConnKind] = []
        for k in model.liveKinds {
            if case .ready(let app) = await model.loadApp(k.id), !app.configured { out.append(k) }
        }
        missing = out
    }
}

/// One connection: who it is, its state as a sentence, when it was used and by how many. Actions fade in on hover; a card
/// that needs you shows "Sign in again" all the time.
struct ConnCard: View {
    let model: ConnectionsModel
    let item: ConnItem
    @State private var menuOpen = false

    /// The rarer actions: Test and Disconnect stay on the card.
    private var menuItems: [CoreDropdownItem] {
        let need = item.status == .needsLook
        return [
            CoreDropdownItem("Rename", symbol: "pencil", enabled: !need) { ConnDialogs.openRename(model, item) },
            item.isDefault
                ? CoreDropdownItem("Clear default", symbol: "star.slash", enabled: !need) {
                    Task { await model.clearDefault(item) }
                }
                : CoreDropdownItem("Use by default", symbol: "star", enabled: !need) {
                    Task { await model.makeDefault(item) }
                },
            CoreDropdownItem("Who can use it", symbol: "lock.shield", enabled: !need) {
                ConnDialogs.openAccess(model, item)
            },
            CoreDropdownItem("Replace token", symbol: "key") { ConnDialogs.openReplace(model, item) },
        ]
    }

    var body: some View {
        let (label, tone, symbol) = ConnLook.badge(item.status)
        let need = item.status == .needsLook
        let on = model.cursor == item.id
        AccPanel(spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s3) {
                ConnTile(kind: item.kind)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Space.s2) {
                        Text(item.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(2)
                            .layoutPriority(1)
                        if item.isDefault { AccChip(text: "Default") }
                    }
                    Text(item.identity).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                StateBadge(label, tone: tone, symbol: symbol).layoutPriority(2)
            }
            Text(
                need
                    ? "\(item.reason ?? "This sign-in stopped working.") Agents can't use it until you sign in again."
                    : model.access(item)
            )
            .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            if let t = model.tested[item.id] {
                Label(t, systemImage: "checkmark.seal").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
            }
            HStack {
                Text(when).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                Spacer()
                Text(item.users <= 1 ? "Only you" : "You and \(item.users - 1) agents").coreFont(size: MacTextSize.meta)
                .foregroundStyle(GlassInk.secondary)
            }
            HStack(spacing: Space.s1) {
                if need {
                    AccLink(title: "Sign in again", symbol: "arrow.clockwise") {
                        ConnDialogs.openConnect(model, kind: item.kind, again: item.id)
                    }
                }
                AccLink(title: model.testing == item.id ? "Testing…" : "Test", symbol: "play") {
                    Task { await model.test(item) }
                }
                if !model.host.shell.settings.hidden.contains("audit") {
                    AccLink(title: "History", symbol: "clock.arrow.circlepath") { model.openHistory(item) }
                        .help("Opens Settings, Audit, showing only what happened to this connection")
                }
                Spacer(minLength: 0)
                AccLink(title: "Disconnect", symbol: "trash", danger: true) { ConnDialogs.openDisconnect(model, item) }
                CoreDropdown(items: menuItems, isPresented: $menuOpen) {
                    Image(systemName: "ellipsis").coreFont(size: MacTextSize.body, weight: .semibold)
                        .foregroundStyle(GlassInk.primary)
                        .frame(width: 30, height: 26)
                        .background(GlassInk.well, in: coreShape(7))
                        .overlay { coreShape(7).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
                        .contentShape(coreShape(7))
                }
                .help("More: rename, default, who can use it, replace the token")
                .accessibilityLabel("More actions for \(item.name)")
            }
        }
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.blue.opacity(on ? 0.7 : 0), lineWidth: 1.5) }
        .contextMenu {
            ForEach(menuItems) { i in
                Button(i.title, role: i.destructive ? .destructive : nil) { i.run() }.disabled(!i.enabled)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.name), \(label)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var when: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        if let u = item.lastUsed { return "Used \(f.localizedString(for: u, relativeTo: Date()))" }
        if let c = item.lastChecked { return "Checked \(f.localizedString(for: c, relativeTo: Date()))" }
        return "Not used yet"
    }
}
