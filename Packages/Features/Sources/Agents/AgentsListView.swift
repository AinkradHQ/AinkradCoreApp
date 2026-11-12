import CoreUI
import SwiftUI

/// The AI Sessions list, variant B (N42): a sidebar of what needs you, when, projects and runners, and a flat dense list. Built
/// for hundreds of sessions: lazy rows, pages loaded from the Core as you scroll, ended ones archived after 14 days.
struct AgentsListView: View {
    @Bindable var model: AgentsModel
    @Environment(\.corePalette) private var palette
    @FocusState private var listFocus: Bool
    @FocusState private var searchFocus: Bool
    @State private var collapsed: Set<SessionSection> = [.earlier]

    var body: some View {
        let index = model.makeIndex()
        let groups = index.groups(scope: model.scope, filters: model.filters)
        let rows = groups.filter { !collapsed.contains($0.section) || !model.filters.search.isEmpty }.flatMap(\.rows)
        GeometryReader { geo in
            let compact = geo.size.width < 760
            VStack(alignment: .leading, spacing: 0) {
                header(index)
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
                    NoticeBanner(notice: InlineNotice(title: "Live updates stopped", detail: why, tone: .fail))
                        .padding([.horizontal, .bottom], Space.s3)
                }
                filterBar(index, compact: compact)
                HStack(alignment: .top, spacing: Space.s2) {
                    if !compact { SessionSidebar(model: model, index: index).frame(width: 210) }
                    content(groups, rows, compact: compact)
                }
                .padding(.horizontal, Space.s3)
                keyHints
            }
        }
        .foregroundStyle(GlassInk.primary)
        .paneLook(AgentPrefs.shared.look)
        .clipShape(coreShape(Radius.cardMac))
        .accessibilityElement(children: .contain)
        .background {
            Button("") { searchFocus = true }.keyboardShortcut("f", modifiers: .command).opacity(0)
                .accessibilityHidden(true)
        }
    }

    // MARK: header and filters

    private func header(_ index: SessionIndex) -> some View {
        let active = index.counts[.active] ?? 0
        let waiting = model.waitingOnYou
        return HStack(spacing: Space.s3) {
            Text("AI Sessions").coreFont(size: MacTextSize.large, weight: .bold)
            Text("\(model.sessions.items.count)").coreFont(size: MacTextSize.meta, weight: .semibold)
                .padding(.horizontal, 7).frame(height: 20).background(GlassInk.well, in: coreShape(5))
                .foregroundStyle(GlassInk.secondary)
            Text(
                [
                    "\(active) active", AgentWords.cost(model.sessions.totalCostMicros).map { "\($0) in total" },
                ].compactMap { $0 }.joined(separator: " · ")
            )
            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            Spacer(minLength: Space.s3)
            AppActionTile(
                title: waiting > 0 ? "Approvals \(waiting)" : "Approvals", symbol: "lock.shield", key: "",
                hue: waiting > 0 ? GlassInk.blue : GlassInk.slate, pulse: waiting > 0
            ) { model.openInbox() }
            .accessibilityLabel(waiting > 0 ? "Approvals, \(waiting) waiting" : "Approvals")
            AppActionTile(title: "New AI session", symbol: "plus", key: "⌘N", hue: GlassInk.blue, prominent: true) {
                model.openNewSession()
            }
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
    }

    private func filterBar(_ index: SessionIndex, compact: Bool) -> some View {
        HStack(spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: "magnifyingglass").foregroundStyle(GlassInk.secondary)
                TextField("Search title, first message, folder or project", text: $model.filters.search)
                    .textFieldStyle(.plain).focused($searchFocus)
                    .onKeyPress(.escape) {
                        model.filters.search = ""
                        searchFocus = false
                        listFocus = true
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        searchFocus = false
                        listFocus = true
                        return .handled
                    }
                    .accessibilityLabel("Search AI sessions")
                Text("⌘F").coreFont(size: 10, weight: .medium).padding(.horizontal, 5)
                    .background(GlassInk.lift(0.14), in: coreShape(4)).foregroundStyle(GlassInk.secondary)
            }
            .coreFont(size: MacTextSize.body).padding(.horizontal, Space.s3).frame(height: 34)
            .background(GlassInk.well, in: coreShape(Radius.control))
            .overlay {
                coreShape(Radius.control).strokeBorder(searchFocus ? GlassInk.blue : GlassInk.wellEdge, lineWidth: 1)
            }
            if compact { scopeMenu }
            filter(
                "Tool", model.filters.tool.map(AgentWords.toolName), all: "Any tool",
                items: ["claude", "codex", "opencode", "agy"].map { t in
                    (AgentWords.toolName(t), model.filters.tool == t, { model.filters.tool = t })
                }, clear: { model.filters.tool = nil })
            if !compact {
                filter(
                    "Runner", model.filters.runner.map { model.runnerName($0) }, all: "Any runner",
                    items: index.runners.map { r in
                        (model.runnerName(r.id), model.filters.runner == r.id, { model.filters.runner = r.id })
                    }, clear: { model.filters.runner = nil })
                filter(
                    "Project", model.filters.project, all: "Any project",
                    items: index.projects.map { p in
                        (p.name, model.filters.project == p.name, { model.filters.project = p.name })
                    }, clear: { model.filters.project = nil })
            }
            filter(
                "State", model.filters.state.map(Self.facetWords), all: "Any state",
                items: SessionFilters.Facet.allCases.map { f in
                    (Self.facetWords(f), model.filters.state == f, { model.filters.state = f })
                }, clear: { model.filters.state = nil })
        }
        .padding(.horizontal, Space.s4).padding(.bottom, Space.s2)
    }

    private static func facetWords(_ f: SessionFilters.Facet) -> String {
        switch f {
        case .needsYou: "Needs you"
        case .running: "Running"
        case .waiting: "Waiting for you"
        case .ended: "Ended"
        }
    }

    private func filter(
        _ name: String, _ value: String?, all: String, items: [(String, Bool, @MainActor @Sendable () -> Void)],
        clear: @escaping @MainActor @Sendable () -> Void
    ) -> some View {
        CoreDropdown(
            items: [CoreDropdownItem(all, checked: value == nil, run: clear)]
                + items.map { i in CoreDropdownItem(i.0, checked: i.1, run: i.2) }
        ) {
            HStack(spacing: 5) {
                Text("\(name):").foregroundStyle(GlassInk.secondary)
                Text(value ?? all).fontWeight(.semibold).lineLimit(1)
                Image(systemName: "chevron.down").coreFont(size: 9, weight: .semibold).foregroundStyle(
                    GlassInk.secondary)
            }
            .coreFont(size: MacTextSize.body).padding(.horizontal, Space.s3).frame(height: 34)
            .background(GlassInk.well, in: coreShape(Radius.control))
            .overlay {
                coreShape(Radius.control).strokeBorder(
                    value == nil ? GlassInk.wellEdge : GlassInk.blue.opacity(0.7), lineWidth: 1)
            }
        }
        .accessibilityLabel("\(name) filter, \(value ?? all)")
    }

    /// Narrow panes drop the sidebar: its entries become one menu.
    private var scopeMenu: some View {
        let all: [(String, SessionScope)] = [
            ("Active", .active), ("Needs you", .needsYou), ("Running", .running), ("Waiting for you", .waiting),
            ("Pinned", .pinned), ("Today", .today), ("Yesterday", .yesterday), ("This week", .thisWeek),
            ("Earlier", .earlier), ("Archive", .archive),
        ]
        return CoreDropdown(
            items: all.map { a in CoreDropdownItem(a.0, checked: model.scope == a.1) { model.scope = a.1 } }
        ) {
            HStack(spacing: 5) {
                Text(all.first { $0.1 == model.scope }?.0 ?? "Group").fontWeight(.semibold)
                Image(systemName: "chevron.down").coreFont(size: 9, weight: .semibold).foregroundStyle(
                    GlassInk.secondary)
            }
            .coreFont(size: MacTextSize.body).padding(.horizontal, Space.s3).frame(height: 34)
            .background(GlassInk.well, in: coreShape(Radius.control))
            .overlay { coreShape(Radius.control).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        }
    }

    private var keyHints: some View {
        Text("\(coreArrowKeys()) move · ↩ open · ⌘N new AI session · ⌘F search · P pin · E end · A archive")
            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, Space.s2)
    }

    // MARK: rows

    @ViewBuilder
    private func content(_ groups: [SessionGroup], _ rows: [AgentSessionInfo], compact: Bool) -> some View {
        switch model.sessions.load {
        case .idle, .loading:
            VStack(spacing: Space.s2) {
                ForEach(0..<9, id: \.self) { _ in CoreSkeleton(coreShape(Radius.control)).frame(height: 36) }
            }
            .padding(.vertical, Space.s2).frame(maxHeight: .infinity, alignment: .top)
            .accessibilityElement(children: .ignore).accessibilityLabel("Loading AI sessions")
        case .failed(let why):
            CoreStateCard(
                symbol: "exclamationmark.triangle", title: "Could not load AI sessions", line: why,
                primary: CoreAction("Try again") { model.retryList() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            if model.sessions.items.isEmpty {
                CoreStateCard(
                    symbol: "text.cursor", title: "No AI sessions yet",
                    line:
                        "Open one and it runs on a runner of the Home Core, like typing claude in a terminal. You can close this Mac; it keeps going.",
                    primary: CoreAction("New AI session") { model.openNewSession() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty && !model.sessions.hasMore {
                CoreStateCard(
                    symbol: "line.3.horizontal.decrease", title: "Nothing here",
                    line: model.filters.isEmpty ? "No AI sessions in this group." : "No AI sessions match the filters.",
                    primary: model.filters.isEmpty
                        ? nil : CoreAction("Clear filters") { model.filters = SessionFilters() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list(groups, rows, compact: compact)
            }
        }
    }

    private func columnHeads(compact: Bool) -> some View {
        HStack(spacing: Space.s3) {
            Text("Title and project").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 22 + Space.s3)
            if !compact { Text("Runner").frame(width: SessionColumns.runner, alignment: .leading) }
            Text("State").frame(width: SessionColumns.state, alignment: .leading)
            if !compact { Text("Last activity").frame(width: SessionColumns.activity, alignment: .leading) }
            Text("Cost").frame(width: SessionColumns.cost, alignment: .trailing)
        }
        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).padding(.horizontal, Space.s3)
        .frame(height: 24)
    }

    /// Keyboard: the list holds focus, ↑↓ move the cursor, ↩ opens, P pins, E ends, A archives.
    private func list(_ groups: [SessionGroup], _ rows: [AgentSessionInfo], compact: Bool) -> some View {
        let waitingIDs = Set(model.pending.map(\.session))
        let now = Date()
        return VStack(alignment: .leading, spacing: 0) {
            columnHeads(compact: compact)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                        ForEach(groups) { g in
                            SectionHeader(group: g, collapsed: collapsed.contains(g.section)) {
                                if collapsed.contains(g.section) {
                                    collapsed.remove(g.section)
                                } else {
                                    collapsed.insert(g.section)
                                }
                            }
                            if !collapsed.contains(g.section) || !model.filters.search.isEmpty {
                                ForEach(g.rows) { s in
                                    SessionRow(
                                        session: s, title: model.title(s), runner: model.runnerName(s.runner),
                                        waiting: waitingIDs.contains(s.id), pinned: model.pinned.contains(s.id),
                                        selected: model.selected == s.id, compact: compact, now: now,
                                        onPin: { model.togglePin(s.id) }, onEnd: { model.confirmEnd(s.id) }
                                    )
                                    .id(s.id)
                                    .onTapGesture(count: 2) { model.openSession(s.id) }
                                    .onTapGesture {
                                        model.selected = s.id
                                        listFocus = true
                                    }
                                    .accessibilityAddTraits(
                                        model.selected == s.id ? [.isSelected, .isButton] : .isButton
                                    )
                                    .accessibilityAction { model.openSession(s.id) }
                                    .onAppear { model.loadTitle(s.id) }
                                }
                            }
                        }
                        if model.sessions.hasMore {
                            // The next page loads when this scrolls into view: only what is on screen costs anything.
                            Text("Older AI sessions load as you scroll").coreFont(size: MacTextSize.meta)
                                .foregroundStyle(palette.text2).frame(maxWidth: .infinity).padding(Space.s3)
                                .onAppear { model.loadMore() }
                        }
                    }
                    .padding(.bottom, Space.s2)
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
                .onKeyPress(.home) { move(rows, -rows.count, proxy) }
                .onKeyPress(.end) { move(rows, rows.count, proxy) }
                .onKeyPress(.return) { open(rows) }
                .onKeyPress(.space) { open(rows) }
                .onKeyPress(characters: .letters) { press in
                    guard let key = PaneKeys.shortcut(press.characters, typing: searchFocus),
                        let id = model.selected ?? rows.first?.id
                    else { return .ignored }
                    switch key {
                    case "p": model.togglePin(id)
                    case "e": model.confirmEnd(id)
                    case "a": model.toggleArchive(id)
                    default: return .ignored
                    }
                    return .handled
                }
                .accessibilityLabel("AI sessions")
            }
        }
    }

    private func open(_ rows: [AgentSessionInfo]) -> KeyPress.Result {
        guard let id = model.selected ?? rows.first?.id else { return .ignored }
        model.openSession(id)
        return .handled
    }

    private func move(_ rows: [AgentSessionInfo], _ step: Int, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !rows.isEmpty else { return .ignored }
        let i = rows.firstIndex { $0.id == model.selected } ?? (step > 0 ? -1 : rows.count)
        let next = rows[min(max(i + step, 0), rows.count - 1)].id
        model.selected = next
        proxy.scrollTo(next)
        return .handled
    }
}

/// The one question about macOS notifications, in the app's own words, before macOS is asked.
struct NotificationAsk: View {
    @Bindable var model: AgentsModel
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Label("Get told when an AI session needs you", systemImage: "bell").coreFont(
                size: MacTextSize.headline, weight: .semibold)
            Text("Ainkrad can show a macOS banner for each new approval. macOS will ask you to allow it once.")
                .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s2) {
                Spacer(minLength: 0)
                Button("Not now") { model.declineNotificationsForNow() }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                Button("Turn on") { Task { await model.turnOnNotifications() } }
                    .buttonStyle(CoreButtonStyle(.prominent, size: .small))
            }
        }
        .padding(Space.s3)
        .background(palette.glassCard, in: coreShape(Radius.row))
        .overlay { coreShape(Radius.row).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
        .accessibilityElement(children: .contain)
    }
}
