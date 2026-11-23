import CoreUI
import SwiftUI

/// The Brain (mockups 15 and 16) as one app: the sidebar with the search field, Home, the four areas, Places, then what
/// needs a look (To check), where it reads from (Sources) and what it did (Activity); beside it the chosen section.
/// ⌘1 to ⌘9 pick a section, ⌘E searches everything, ⌘I opens Import.
struct BrainCalmView: View {
    let brain: BrainModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            CalmSide(brain: brain)
            VStack(alignment: .leading, spacing: Space.s3) {
                if let n = brain.notice ?? brain.calm.notice {
                    CoreNotice(symbol: "exclamationmark.triangle", title: n, tone: .fail) {
                        if brain.notice != nil {
                            Button("Dismiss") { brain.dismissNotice() }
                                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        }
                    }
                }
                BrainConditions(model: brain)
                BrainSection(brain: brain)
                    .id(brain.currentTab)
                    .transition(.opacity)
            }
            .padding(.horizontal, Space.s6).padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .animation(Motion.out(Motion.ui), value: brain.currentTab)
        .background {
            Button("Import into the Brain") { brain.openImport() }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(brain.service?.importRoutes == nil)
                .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
        }
        .task { if brain.calmAvailable { await brain.calm.reload() } }
        .accessibilityIdentifier("brain-calm")
    }
}

/// The sidebar: the search field, the sections with their keys and counts, and the sample label at the foot.
private struct CalmSide: View {
    let brain: BrainModel
    @FocusState private var searching: Bool

    var body: some View {
        let calm = brain.calm
        VStack(alignment: .leading, spacing: 2) {
            if brain.visibleTabs.contains(.records) { search.padding(.bottom, Space.s2) }
            ForEach(Array(brain.sidebarTabs.enumerated()), id: \.element) { i, t in
                // The areas, then a gap before what needs a look and how the Brain runs.
                if t == .inbox || (t == .sources && !brain.sidebarTabs.contains(.inbox)) {
                    Spacer().frame(height: Space.s3)
                }
                CoreRow(t.title, symbol: t.symbol, selected: brain.currentTab == t, action: { pick(t) }) {
                    HStack(spacing: Space.s2) {
                        let n = brain.tabCount(t)
                        if n > 0 {
                            CountBadge(n, tone: .needsYou, label: t.title)
                        } else if let c = count(t) {
                            Text(c.formatted()).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                                .monospacedDigit().contentTransition(.numericText())
                        }
                    }
                    .fixedSize()
                }
                .help(i < 9 ? "\(t.title) (⌘\(i + 1))" : t.title)
                .keyboardShortcut(
                    i < 9 ? KeyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command) : nil
                )
                .accessibilityIdentifier("brain-area-\(t.calmPage?.rawValue ?? t.rawValue)")
            }
            Spacer(minLength: Space.s4)
            if brain.isSample {
                AppStatChip("testtube.2", "Sample data", GlassInk.slate).help(BrainWords.sampleLabel)
                    .accessibilityLabel(BrainWords.sampleLabel)
            }
        }
        .padding(Space.s3)
        .frame(width: Space.s8 * 9)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: calm.searchAsked) { searching = true }
        .background {
            Button("Search everything") {
                brain.go(.records)
                searching = true
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(!brain.visibleTabs.contains(.records))
            .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    /// "Search everything Brain knows": typing opens the search section; Esc clears it.
    private var search: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "magnifyingglass").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            TextField("Search everything", text: Bindable(brain.calm).query)
                .textFieldStyle(.plain).focused($searching)
                .onChange(of: brain.calm.query) { _, q in
                    if !q.isEmpty, brain.currentTab != .records { brain.go(.records) }
                }
                .onSubmit { brain.go(.records) }
                .onKeyPress(.escape) {
                    guard !brain.calm.query.isEmpty else { return .ignored }
                    brain.calm.query = ""
                    return .handled
                }
                .accessibilityLabel("Search everything Brain knows")
            CoreKeycap("⌘E").accessibilityHidden(true)
        }
        .padding(.horizontal, Space.s3)
        .frame(minHeight: MacSize.controlLg + Space.s1)
        .coreFieldSurface(focused: searching)
        .accessibilityIdentifier("brain-search")
    }

    /// The quiet count beside an area or Places, as the Core has it.
    private func count(_ t: BrainTab) -> Int? {
        guard brain.calmAvailable else { return nil }
        if t == .rooms { return PlaceCards.count(brain) }
        return t.calmPage?.area.flatMap { brain.calm.summary($0)?.count }
    }

    private func pick(_ t: BrainTab) {
        withAnimation(Motion.out(Motion.ui)) {
            if t == .rooms { brain.placeOpen = false }
            if t != .rooms { brain.closeInspect() }
            brain.go(t)
        }
    }
}

/// The chosen section. The old console's views, each under a page head with its own actions.
private struct BrainSection: View {
    let brain: BrainModel

    var body: some View {
        switch brain.currentTab {
        case .overview:
            if brain.calmAvailable {
                CalmHome(brain: brain)
            } else {
                page("Home", "How the Brain is doing, and what needs you") { OverviewTab(model: brain) }
            }
        case .me, .rules, .knowledge, .timeline: CalmArea(brain: brain)
        case .rooms: RoomsTab(model: brain)
        case .inbox: if servesInbox { CheckPage(brain: brain) } else { inbox }
        case .sources:
            if brain.calmAvailable {
                BrainSourcesPage(brain: brain)
            } else {
                page("Sources", "Where Brain reads from, and what it read") {
                    if let sync = brain.sync {
                        SyncBannerView(brain: brain, sync: sync)
                        SourcesTab(brain: brain, sync: sync)
                    }
                } actions: {
                    if let sync = brain.sync { SyncNowTile(sync: sync) }
                }
            }
        case .activity: BrainActivityPage(brain: brain)
        case .checks:
            scroll {
                if brain.isSample { ChecksTab(model: brain) } else { BrainComingLater(title: "Checks") }
            }
        case .records: ExploreRecordsTab(brain: brain)
        }
    }

    private var servesInbox: Bool { brain.service?.servesCandidates == true }

    /// To check: what Brain is not sure about. The candidates fill the page (their list and detail scroll on their own).
    @ViewBuilder private var inbox: some View {
        if servesInbox {
            VStack(alignment: .leading, spacing: Space.s3) {
                BrainPageHead("To check", "What Brain is not sure about yet. Keep it, change it or let it go.") {
                    if let sync = brain.sync { SyncNowTile(sync: sync) }
                }
                CandidateInboxTab(model: brain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            page("To check", "What Brain is not sure about yet. Keep it, change it or let it go.") {
                if brain.inboxState.list != .noRoom { RoomBar(model: brain) }
                CandidateInboxTab(model: brain)
            }
        }
    }

    private func scroll<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func page<C: View>(_ title: String, _ sub: String, @ViewBuilder _ content: () -> C) -> some View {
        page(title, sub, content) { EmptyView() }
    }

    private func page<C: View, A: View>(
        _ title: String, _ sub: String, @ViewBuilder _ content: () -> C, @ViewBuilder actions: () -> A
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            BrainPageHead(title, sub, actions: actions)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) { content() }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// A section's title, its line under it and its actions on the right (mockup 15's page head).
struct BrainPageHead<Actions: View>: View {
    let title: String
    let sub: String
    let actions: Actions

    init(_ title: String, _ sub: String, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.title = title
        self.sub = sub
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).coreFont(size: MacTextSize.title, weight: .semibold).accessibilityAddTraits(.isHeader)
                Text(sub).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: Space.s3)
            actions
        }
    }
}
