import CoreUI
import SwiftUI

/// The Connections pane (CN1, CN6): page tiles and the Connect action in the header, the page, status chips at the foot.
struct ConnectionsView: View {
    let model: ConnectionsModel
    @FocusState private var paneFocus: Bool

    private func arrow(_ step: Int) -> KeyPress.Result {
        guard model.page == .list else { return .ignored }
        withAnimation(.smooth(duration: 0.2)) { model.move(step) }
        return .handled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppHeader {
                AppFilterTile(title: "Connections", count: model.items.count, on: model.page == .list, key: "⌘1") {
                    withAnimation(.smooth(duration: 0.3)) { model.page = .list }
                }
                .keyboardShortcut("1", modifiers: .command)
                AppFilterTile(title: "Activity", count: -1, on: model.page == .activity, key: "⌘2") {
                    withAnimation(.smooth(duration: 0.3)) { model.page = .activity }
                }
                .keyboardShortcut("2", modifiers: .command)
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
                .font(.system(size: MacTextSize.body))
                .foregroundStyle(GlassInk.primary)
                .padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .focusable()
            .focused($paneFocus)
            .focusEffectDisabled()
            .onAppear { paneFocus = true }
            .onKeyPress(.downArrow) { arrow(1) }
            .onKeyPress(.rightArrow) { arrow(1) }
            .onKeyPress(.upArrow) { arrow(-1) }
            .onKeyPress(.leftArrow) { arrow(-1) }
            .onKeyPress(.return) { model.key("↩") ? .handled : .ignored }
            .onKeyPress(.delete) { model.key("⌫") ? .handled : .ignored }
            .onKeyPress(.escape) {
                guard model.cursor != nil else { return .ignored }
                model.cursor = nil
                return .handled
            }
            .onKeyPress(characters: .letters) { model.key($0.characters.lowercased()) ? .handled : .ignored }
            if model.page == .list && !model.items.isEmpty {
                HStack(spacing: Space.s2) {
                    AppStatChip("checkmark.seal.fill", "\(model.connected) connected", GlassInk.green)
                    if model.needLook > 0 {
                        AppStatChip("exclamationmark.triangle.fill", "\(model.needLook) need a look", GlassInk.orange)
                    }
                    Spacer(minLength: 0)
                    Text(
                        model.cursor == nil
                            ? "↑↓ move · ⌘N connect · ⌘2 activity"
                            : "↩ who can use it · T test · R rename · D default · ⌫ disconnect"
                    ).font(.system(size: MacTextSize.meta))
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
                Group {
                    if model.page == .activity { ConnActivityPage(model: model) } else { ConnListPage(model: model) }
                }
                .transition(.opacity)
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

/// CN1: one section per kind with its connections as cards, the kinds coming later, or the empty state.
struct ConnListPage: View {
    let model: ConnectionsModel
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
                                Text(k.name).font(.system(size: MacTextSize.headline, weight: .semibold))
                                let n = model.items.filter { $0.kind == k.id }.count
                                Text("\(n) connection\(n == 1 ? "" : "s")").font(.system(size: MacTextSize.meta))
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
            if !model.laterKinds.isEmpty {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Text("Coming later").font(.system(size: MacTextSize.headline, weight: .semibold))
                    LazyVGrid(columns: columns, alignment: .leading, spacing: Space.s3) {
                        ForEach(model.laterKinds) { k in
                            AccPanel {
                                HStack(spacing: Space.s3) {
                                    ConnTile(kind: k.id)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(k.name).font(.system(size: MacTextSize.body, weight: .semibold))
                                        Text(k.say).font(.system(size: MacTextSize.meta)).foregroundStyle(
                                            GlassInk.secondary)
                                    }
                                    Spacer()
                                    StateBadge("Not yet", tone: .queue, symbol: "clock")
                                }
                            }
                            .opacity(0.6)
                        }
                    }
                }
            }
        }
    }

    private var empty: some View {
        AccStateCard(
            symbol: "link", title: "Nothing connected yet",
            text:
                "Sign in to GitHub or Jira once, here. Core keeps the sign-in safe and lets your agents read issues and code. They can't change anything until you allow it."
        ) {
            ForEach(model.liveKinds) { k in
                AppActionTile(
                    title: "Connect \(k.name)", symbol: ConnLook.symbol(k.id), key: "", hue: GlassInk.blue,
                    prominent: true
                ) {
                    ConnDialogs.openConnect(model, kind: k.id)
                }
            }
            ForEach(model.liveKinds) { k in
                AccLink(title: "\(k.name) app registration", symbol: "gearshape") { ConnDialogs.openApp(model, k) }
            }
        }
    }
}

/// One connection: who it is, its state as a sentence, when it was used and by how many. Actions fade in on hover; a card
/// that needs you shows "Sign in again" all the time.
struct ConnCard: View {
    let model: ConnectionsModel
    let item: ConnItem
    @State private var hovering = false

    var body: some View {
        let (label, tone, symbol) = ConnLook.badge(item.status)
        let need = item.status == .needsLook
        let on = model.cursor == item.id
        AccPanel(spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s3) {
                ConnTile(kind: item.kind)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Space.s2) {
                        Text(item.name).font(.system(size: MacTextSize.body, weight: .semibold)).lineLimit(1)
                        if item.isDefault { AccChip(text: "Default") }
                    }
                    Text(item.identity).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                StateBadge(label, tone: tone, symbol: symbol)
            }
            Text(
                need
                    ? "\(item.reason ?? "This sign-in stopped working.") Agents can't use it until you sign in again."
                    : model.access(item)
            )
            .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            if let t = model.tested[item.id] {
                Label(t, systemImage: "checkmark.seal").font(.system(size: MacTextSize.meta))
                    .foregroundStyle(GlassInk.secondary)
            }
            HStack {
                Text(when).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                Spacer()
                Text(item.users <= 1 ? "Only you" : "You and \(item.users - 1) agents").font(
                    .system(size: MacTextSize.meta)
                )
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
                if !need {
                    AccLink(title: "Rename", symbol: "pencil") { ConnDialogs.openRename(model, item) }
                    if item.isDefault {
                        AccLink(title: "Clear default", symbol: "star.slash") {
                            Task { await model.clearDefault(item) }
                        }
                    } else {
                        AccLink(title: "Use by default", symbol: "star") { Task { await model.makeDefault(item) } }
                    }
                    AccLink(title: "Who can use it", symbol: "lock.shield") { ConnDialogs.openAccess(model, item) }
                }
                Spacer(minLength: 0)
                AccLink(title: "Disconnect", symbol: "trash", danger: true) { ConnDialogs.openDisconnect(model, item) }
            }
            .opacity(need || hovering || on ? 1 : 0)
            .allowsHitTesting(need || hovering || on)
            .animation(.smooth(duration: 0.2), value: hovering)
            HStack {
                AccLink(
                    title: "Replace token", symbol: "key",
                    help: "Paste a new token if this one was changed or ran out."
                ) { ConnDialogs.openReplace(model, item) }
                Spacer(minLength: 0)
            }
            .opacity(need || hovering || on ? 1 : 0)
            .allowsHitTesting(need || hovering || on)
            .animation(.smooth(duration: 0.2), value: hovering)
        }
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.blue.opacity(on ? 0.7 : 0), lineWidth: 1.5) }
        .onHover { hovering = $0 }
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
