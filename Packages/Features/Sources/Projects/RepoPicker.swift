import CoreUI
import SwiftUI

/// What the picker has to show: the Core's GitHub list, or (while the Core cannot give one) only pasted links.
enum RepoCatalogState: Equatable {
    case loading
    case ready([PickRepo])
    case unavailable
    /// The Core could not read GitHub (refused, unreachable, rate limited); the words say which.
    case failed(CatalogProblem)
}

/// The repo picker of the Advanced sheet and of Add Repos: a search field over the repos grouped by org, each a checkbox row.
/// A pasted repo link becomes a row of its own, so a repo can be added before the Core lists GitHub (see `RepoCatalog`).
struct RepoPicker: View {
    let model: ProjectsModel
    @Binding var picked: Set<String>
    @Binding var pasted: [PickRepo]
    /// nil: the list takes all the room it is given (the wizard).
    var height: CGFloat? = Space.s8 * 7
    /// The repos the project already has: shown as such and left out of the picks.
    var existing: [RepoItem] = []
    @State private var query = ""
    @FocusState private var searching: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            searchField
            selectionLine
            list
        }
        .task { await model.loadCatalog() }
        // What is typed filters the list at once; after a pause the Core also searches GitHub, and adds what it finds.
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { await model.searchCatalog(query) }
        }
    }

    /// A search field like Finder's: magnifier, the text, then what it found (or that GitHub is being asked), and a clear.
    private var searchField: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "magnifyingglass").coreFont(size: MacTextSize.body, weight: .medium)
                .foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            TextField(
                "", text: $query, prompt: Text("Search your repos or paste a link").foregroundStyle(GlassInk.secondary)
            )
            .textFieldStyle(.plain).focused($searching).onSubmit(addTypedLink)
            .accessibilityLabel("Search repos")
            if !trimmed.isEmpty {
                Text(searchNote).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .monospacedDigit().contentTransition(.opacity).lineLimit(1).fixedSize()
                CoreIconButton(symbol: "xmark", label: "Clear the search") { query = "" }
            }
        }
        .padding(.horizontal, Space.s3).frame(height: MacSize.controlLg)
        .coreFieldSurface(focused: searching)
        .onExitCommand { if query.isEmpty { searching = false } else { query = "" } }
        .animation(Motion.out(Motion.hover), value: trimmed.isEmpty)
        .onAppear { searching = true }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var shownCount: Int { groups.reduce(0) { $0 + $1.repos.count } }
    private var searchNote: String {
        if model.catalogBusy { return "Searching GitHub…" }
        return shownCount == 1 ? "1 repo" : "\(shownCount) repos"
    }

    /// How many are picked, with a way to clear them; the line keeps its height so nothing below jumps.
    private var selectionLine: some View {
        HStack(spacing: Space.s2) {
            Text(picked.isEmpty ? "Pick one or more" : picked.count == 1 ? "1 selected" : "\(picked.count) selected")
                .coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
                .contentTransition(.numericText()).monospacedDigit()
            if !picked.isEmpty {
                Button("Clear") { picked.removeAll() }.buttonStyle(CoreButtonStyle(.plain, size: .small))
                    .transition(.opacity)
            }
            Spacer()
        }
        .frame(height: MacSize.controlSm)
        .animation(Motion.out(Motion.ui), value: picked.count)
    }

    private var shownIDs: [String] { groups.flatMap { $0.repos.map(\.id) } }

    private func has(_ r: PickRepo) -> Bool { existing.contains { ProjectRules.same($0.remoteURL, r.url) } }

    /// What is wrong with the typed text when it was meant as a link (ssh, a password…); nil for a plain search.
    private var linkProblem: String? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard ProjectRules.looksLikeLink(q), ProjectRules.repo(fromLink: q) == nil else { return nil }
        return ProjectRules.repoLinkProblem(q)
    }

    private var catalogState: RepoCatalogState { model.catalogState }
    private var now: Date { model.now() }

    /// The repos that match the search, by org (the freshest org first) then freshest first; pasted links sit in their own group.
    private var groups: [(org: String, repos: [PickRepo])] {
        var all: [PickRepo] = []
        if case .ready(let r) = catalogState { all = r }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let hit: (PickRepo) -> Bool = {
            q.isEmpty || $0.name.lowercased().contains(q) || $0.org.lowercased().contains(q)
        }
        let fresh: (PickRepo) -> Date = { $0.updatedAt ?? .distantPast }
        let byOrg = Dictionary(grouping: all.filter(hit), by: \.org).mapValues { $0.sorted { fresh($0) > fresh($1) } }
        var out = byOrg.keys.sorted {
            (byOrg[$0]!.first.map(fresh) ?? .distantPast) > (byOrg[$1]!.first.map(fresh) ?? .distantPast)
        }
        .map { ($0, byOrg[$0]!) }
        let mine = pasted.filter(hit)
        if !mine.isEmpty { out.append(("Pasted links", mine)) }
        return out
    }

    /// The search text, when it is a repo link that is not in the list yet.
    private var typedLink: PickRepo? {
        guard let r = ProjectRules.repo(fromLink: query) else { return nil }
        if pasted.contains(where: { $0.url == r.url }) { return nil }
        if case .ready(let all) = catalogState, all.contains(where: { $0.url == r.url }) { return nil }
        return PickRepo(org: "Pasted links", name: r.name, url: r.url)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s1) {
                if let why = linkProblem { CoreFieldError(why).padding(Space.s2) }
                if let link = typedLink, !has(link) {
                    CoreRow("Add link: \(link.name)", subtitle: link.url, symbol: "plus", action: addTypedLink)
                }
                switch catalogState {
                case .loading:
                    ForEach(0..<3, id: \.self) { _ in
                        CoreSkeleton(coreShape(Radius.control)).frame(height: MacSize.controlLg + Space.s2)
                    }
                case .unavailable where pasted.isEmpty && typedLink == nil:
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("Connect GitHub to see your repos. Or paste a repo link above to add one.")
                            .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Connect GitHub") { model.connectGithub() }
                            .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    }
                    .padding(Space.s2)
                case .failed(let why):
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text(why.words).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                        if why.needsConnection {
                            Button("Connect GitHub") { model.connectGithub() }
                                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        } else {
                            Button("Try Again") { Task { await model.loadCatalog() } }
                                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        }
                    }
                    .padding(Space.s2)
                case .ready where groups.isEmpty && typedLink == nil:
                    Text(model.catalogBusy ? "Searching GitHub for “\(trimmed)”…" : "No repo matches “\(trimmed)”.")
                        .foregroundStyle(GlassInk.secondary).padding(Space.s3)
                default: EmptyView()
                }
                ForEach(groups, id: \.org) { g in
                    Text(g.org).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
                        .padding(.horizontal, Space.s3).padding(.top, Space.s3).padding(.bottom, Space.s1)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(g.repos) { r in row(r).transition(.opacity) }
                }
                more
            }
            .padding(Space.s1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        // Soft edges: a row half out of view fades instead of being cut.
        .mask(
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: Space.s2)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: Space.s5)
            }
        )
        .animation(Motion.out(Motion.ui), value: shownIDs)
        .frame(minHeight: height ?? Space.s8 * 4, maxHeight: height ?? .infinity)
        .coreCard(GlassInk.well, radius: Radius.cardMac)
        .clipShape(coreShape(Radius.cardMac))
    }

    /// "Show more" for the next page, and the word that GitHub holds more than the Core reads.
    @ViewBuilder private var more: some View {
        if model.catalogHasMore {
            Button("Show more") { Task { await model.moreCatalog() } }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(model.catalogBusy)
                .padding(Space.s2)
        }
        if model.catalogTruncated {
            Text("GitHub has more repos than Core reads. Search to find more.")
                .foregroundStyle(GlassInk.secondary).padding(Space.s2)
        }
    }

    /// A checkbox and a row: either one toggles the repo. A repo the project already has is marked and cannot be picked.
    @ViewBuilder private func row(_ r: PickRepo) -> some View {
        if has(r) {
            RepoPickRow(repo: r, detail: "Already in this project", on: true, run: nil).opacity(0.6)
        } else {
            pickRow(r)
        }
    }

    private func pickRow(_ r: PickRepo) -> some View {
        RepoPickRow(repo: r, detail: r.detail(now: now), on: picked.contains(r.id)) { toggle(r) }
    }

    private func toggle(_ r: PickRepo) {
        if picked.contains(r.id) { picked.remove(r.id) } else { picked.insert(r.id) }
    }

    /// Return in the search field: a typed link becomes a picked row.
    private func addTypedLink() {
        guard let link = typedLink else { return }
        pasted.append(link)
        picked.insert(link.id)
        query = ""
    }
}

/// One repo in the picker: one compact line (two when it has a description), the check inside the row, and the whole row
/// toggles it. Picked rows carry the accent; hover lifts the well.
private struct RepoPickRow: View {
    let repo: PickRepo
    let detail: String
    let on: Bool
    let run: (() -> Void)?
    @State private var hovering = false
    @Environment(\.coreAccent) private var accent

    var body: some View {
        Button {
            run?()
        } label: {
            HStack(spacing: Space.s3) {
                // The on state: accent fill and a white tick. A repo the project already has is the same, quieter.
                ZStack {
                    coreShape(Radius.chip).fill(on ? (run == nil ? GlassInk.secondary : GlassInk.accent(accent)) : .clear)
                    coreShape(Radius.chip).strokeBorder(on ? .clear : GlassInk.secondary, lineWidth: 1.5)
                    if on { Image(systemName: "checkmark").coreFont(size: MacTextSize.meta, weight: .bold).foregroundStyle(.white) }
                }
                .frame(width: Space.s4 + 2, height: Space.s4 + 2)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(repo.name).coreFont(size: MacTextSize.body, weight: .medium).lineLimit(1)
                    if !detail.isEmpty {
                        Text(detail).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: Space.s2)
            }
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
            .frame(maxWidth: .infinity, minHeight: MacSize.controlLg, alignment: .leading)
            .background(
                on ? GlassInk.accent(accent).opacity(0.16) : hovering ? GlassInk.wellHover : .clear,
                in: coreShape(Radius.control)
            )
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(CoreQuietPressStyle())
        .disabled(run == nil)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .animation(Motion.out(Motion.ui), value: on)
        .accessibilityLabel(repo.name)
        .accessibilityValue(on ? "selected" : "not selected")
        .accessibilityAddTraits(.isButton)
    }
}
