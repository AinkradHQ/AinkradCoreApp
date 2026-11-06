import CoreUI
import SwiftUI

/// The sessions list pane: what waits on you, the filter, one row per session, older ones as you scroll.
struct AgentsListView: View {
    @Bindable var model: AgentsModel
    @Environment(\.corePalette) private var palette
    @FocusState private var listFocus: Bool

    var body: some View {
        let waitingIDs = Set(model.pending.map(\.session))
        // ⌘1 to ⌘4 belong to whichever pane is in front: the Terminals list has the same keys.
        let keysHere = model.shell.activePane == AgentsModel.listPane
        VStack(alignment: .leading, spacing: 0) {
            AppHeader {
                ForEach(Array(filters(waitingIDs.count).enumerated()), id: \.offset) { i, f in
                    AppFilterTile(title: f.1, count: f.2, on: model.filter == f.0, key: "⌘\(i + 1)") {
                        withAnimation(Motion.out(Motion.ui)) { model.filter = f.0 }
                    }
                    .keyboardShortcut(
                        keysHere ? KeyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command) : nil)
                }
            } actions: {
                buttons(waitingIDs.count)
            }
            if model.shouldAskAboutNotifications {
                NotificationAsk(model: model).padding([.horizontal, .bottom], Space.s3)
            }
            if model.link == .reconnecting {
                NoticeBanner(
                    notice: InlineNotice(
                        title: "Reconnecting", detail: "Resuming from where you were. Nothing is lost.",
                        symbol: "arrow.triangle.2.circlepath")
                ).padding([.horizontal, .bottom], Space.s3)
            }
            if case .ended(let why) = model.link {
                NoticeBanner(
                    notice: InlineNotice(
                        title: "Live updates stopped", detail: "Updates from your Core stopped coming in.", tone: .fail)
                )
                .help(why).padding([.horizontal, .bottom], Space.s3)
            }
            content(waitingIDs)
            footer(waitingIDs.count)
        }
        .foregroundStyle(GlassInk.primary)
        // The Terminals app's frame: the pane's glass is a rim, the app's surface sits inside it, rounded.
        .paneLook(AgentPrefs.shared.look)
        .clipShape(coreShape(Radius.cardMac))
        .accessibilityElement(children: .contain)
    }

    /// The Terminals footer: status chips at the left, the keys at the right.
    private func footer(_ waiting: Int) -> some View {
        HStack(spacing: Space.s2) {
            if waiting > 0 { AppStatChip("hand.raised.fill", "\(waiting) waiting on you", GlassInk.orange) }
            AppStatChip("play.fill", "\(model.count(.active)) active", GlassInk.green)
            if let c = AgentWords.cost(model.sessions.totalCostMicros),
                model.sessions.items.contains(where: { $0.usage?.costMicros != nil })
            {
                AppStatChip("dollarsign", c, GlassInk.blue)
            }
            Spacer(minLength: 0)
            Text("↩ open · ← → move · A approvals · C cancel · K kill · R resume").font(.system(size: MacTextSize.meta))
                .foregroundStyle(GlassInk.secondary).lineLimit(1).truncationMode(.tail).layoutPriority(-1)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
    }

    private func filters(_ waiting: Int) -> [(AgentFilter, String, Int)] {
        [
            (.all, "All", model.count(.all)), (.needsYou, "Needs you", waiting),
            (.active, "Active", model.count(.active)),
            (.ended, "Ended", model.count(.ended)),
        ]
    }

    @ViewBuilder
    private func buttons(_ waiting: Int) -> some View {
        AppActionTile(
            title: waiting > 0 ? "Approvals \(waiting)" : "Approvals", symbol: "lock.shield", key: "A",
            hue: waiting > 0 ? GlassInk.orange : GlassInk.slate, prominent: waiting > 0
        ) { model.openInbox() }
        .accessibilityLabel(waiting > 0 ? "Approvals, \(waiting) waiting" : "Approvals")
        AppActionTile(title: "New", symbol: "plus", key: "⌘N", hue: GlassInk.blue, prominent: true) {
            model.openNewSession()
        }
    }

    @ViewBuilder
    private func content(_ waitingIDs: Set<String>) -> some View {
        switch model.sessions.load {
        case .idle, .loading:
            ScrollView { SkeletonRows().padding(.horizontal, Space.s3) }
        case .failed(let why):
            Message(
                symbol: "wifi.exclamationmark", title: "Could not load sessions",
                text: "Check that your Core is reachable, then try again.", help: why, action: "Try again",
                prominent: false
            ) { model.retryList() }
        case .ready:
            let rows = model.shown()
            if model.sessions.items.isEmpty {
                Message(
                    symbol: "play.fill", title: "No agent sessions yet",
                    text: "Start one and it runs on a runner of your Core. You can close this Mac; it keeps going.",
                    action: "New session", prominent: true
                ) { model.openNewSession() }
            } else if rows.isEmpty {
                Message(
                    symbol: "line.3.horizontal.decrease", title: "Nothing here", text: "No sessions match this filter.",
                    action: nil, prominent: false
                ) {}
            } else {
                list(rows, waitingIDs)
            }
        }
    }

    /// The Terminals list's keyboard model: the grid itself holds focus (taken on arrival), one tile is the cursor, arrows move it and scroll, Return or Space opens, C K R act on it, A opens approvals.
    private func list(_ rows: [AgentSessionInfo], _ waitingIDs: Set<String>) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Space.s8 * 11), spacing: Space.s3, alignment: .top)],
                    spacing: Space.s3
                ) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, s in
                        SessionTile(
                            session: s, runner: model.runnerName(s.runner), waiting: waitingIDs.contains(s.id),
                            selected: model.selected == s.id, burn: model.sessions.burn[s.id] ?? []
                        ) { key in act(key, s.id) }
                        .onTapGesture(count: 2) { model.openSession(s.id) }
                        .onTapGesture {
                            withAnimation(Motion.out(Motion.ui)) { model.selected = s.id }
                            listFocus = true
                        }
                        .accessibilityLabel(label(s, waiting: waitingIDs.contains(s.id)))
                        .accessibilityAddTraits(model.selected == s.id ? [.isSelected, .isButton] : .isButton)
                        .accessibilityAction { model.openSession(s.id) }
                        .modifier(RiseIn(index: i))
                        .id(s.id)
                        .onAppear { if s.id == rows.last?.id && model.filter == .all { model.loadMore() } }
                    }
                }
                .padding(.horizontal, Space.s4).padding(.vertical, Space.s1)
                if model.sessions.hasMore && model.filter == .all {
                    Label("Older sessions load as you scroll", systemImage: "arrow.down")
                        .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                        .padding(Space.s4).frame(maxWidth: .infinity)
                }
            }
            .scrollIndicators(.never)
            .focusable()
            .focused($listFocus)
            .focusEffectDisabled()
            .onAppear {
                listFocus = true
                if model.selected == nil || !rows.contains(where: { $0.id == model.selected }) {
                    model.selected = rows.first?.id
                }
            }
            .onKeyPress(.downArrow) { move(rows, 1, proxy) }
            .onKeyPress(.upArrow) { move(rows, -1, proxy) }
            .onKeyPress(.rightArrow) { move(rows, 1, proxy) }
            .onKeyPress(.leftArrow) { move(rows, -1, proxy) }
            .onKeyPress(.home) { move(rows, -rows.count, proxy) }
            .onKeyPress(.end) { move(rows, rows.count, proxy) }
            .onKeyPress(.return) { act("o", rows) }
            .onKeyPress(.space) { act("o", rows) }
            .onKeyPress(characters: .letters) { press in
                let key = press.characters.lowercased()
                if key == "a" {
                    model.openInbox()
                    return .handled
                }
                guard let c = key.first, "ckr".contains(c) else { return .ignored }
                return act(c, rows)
            }
            .accessibilityLabel("Agent sessions")
        }
    }

    /// A tile's action, from its hover buttons or the keyboard: ↩ open, R resume, C cancel, K kill.
    private func act(_ key: Character, _ id: String) {
        switch key {
        case "c": model.confirmCancel(id)
        case "k": model.confirmKill(id)
        case "r": model.resume(id)
        default: model.openSession(id)
        }
    }

    private func act(_ key: Character, _ rows: [AgentSessionInfo]) -> KeyPress.Result {
        guard let id = model.selected ?? rows.first?.id else { return .ignored }
        act(key, id)
        return .handled
    }

    private func move(_ rows: [AgentSessionInfo], _ step: Int, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !rows.isEmpty else { return .ignored }
        let i = rows.firstIndex { $0.id == model.selected } ?? (step > 0 ? -1 : rows.count)
        let next = rows[min(max(i + step, 0), rows.count - 1)].id
        withAnimation(Motion.out(Motion.ui)) { model.selected = next }
        withAnimation(Motion.out(Motion.move)) { proxy.scrollTo(next) }
        return .handled
    }

    private func label(_ s: AgentSessionInfo, waiting: Bool) -> String {
        let st = AgentWords.status(s, waiting: waiting).label
        return "\(AgentWords.harness(s.harness)) on \(model.runnerName(s.runner)), \(st)"
    }
}

private struct Message: View {
    let symbol: String
    let title: String
    let text: String
    var help: String?
    let action: String?
    let prominent: Bool
    let run: () -> Void
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(spacing: Space.s3) {
            IconTile(symbol, hue: GlassInk.slate, size: 64)
            Text(title).font(.system(size: MacTextSize.title, weight: .semibold))
            Text(text).foregroundStyle(palette.text2).multilineTextAlignment(.center).help(help ?? "")
            if let action {
                Button(action, action: run).buttonStyle(CoreButtonStyle(prominent ? .prominent : .secondary))
            }
        }
        .frame(maxWidth: Space.s8 * 10).padding(Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// The one question about macOS notifications, in the app's own words, before macOS is asked.
struct NotificationAsk: View {
    @Bindable var model: AgentsModel
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Label("Get told when an agent needs you", systemImage: "bell").font(
                .system(size: MacTextSize.headline, weight: .semibold))
            Text("Ainkrad can show a macOS banner for each new approval. macOS will ask you to allow it once.")
                .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s2) {
                Button("Not now") { model.declineNotificationsForNow() }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                Spacer(minLength: 0)
                Button("Turn on") { Task { await model.turnOnNotifications() } }
                    .buttonStyle(CoreButtonStyle(.prominent, size: .small))
            }
        }
        .padding(Space.s3)
        .coreWell()
        .accessibilityElement(children: .contain)
    }
}

/// Rows rise in one after another the first time they show.
struct RiseIn: ViewModifier {
    let index: Int
    @State private var shown = false
    func body(content: Content) -> some View {
        content.coreRise(shown, index).onAppear { shown = true }
    }
}
