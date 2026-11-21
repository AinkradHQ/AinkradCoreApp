import CoreUI
import SwiftUI

/// What the picker has to show: the Core's GitHub list, or (while the Core cannot give one) only pasted links.
enum RepoCatalogState: Equatable {
    case loading
    case ready([PickRepo])
    case unavailable
}

/// The repo picker of the Advanced sheet and of Add Repos: a search field over the repos grouped by org, each a checkbox row.
/// A pasted repo link becomes a row of its own, so a repo can be added before the Core lists GitHub (see `RepoCatalog`).
struct RepoPicker: View {
    let model: ProjectsModel
    @Binding var picked: Set<String>
    @Binding var pasted: [PickRepo]
    var height: CGFloat = Space.s8 * 7
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            CoreTextField(
                picked.isEmpty ? "Repos from GitHub" : "Repos from GitHub · \(picked.count) selected",
                placeholder: "Search your repos or paste a link", text: $query, onSubmit: addTypedLink)
            list
        }
        .task { await model.loadCatalog() }
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
                if let link = typedLink {
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
                case .ready where groups.isEmpty && typedLink == nil:
                    Text("No repo matches “\(query)”.").foregroundStyle(GlassInk.secondary).padding(Space.s2)
                default: EmptyView()
                }
                ForEach(groups, id: \.org) { g in
                    Text(g.org).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
                        .padding(.horizontal, Space.s2).padding(.top, Space.s2)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(g.repos) { r in row(r) }
                }
            }
            .padding(Space.s1)
        }
        .scrollIndicators(.never)
        .frame(height: height)
        .coreCard(GlassInk.well, radius: Radius.cardMac)
        .clipShape(coreShape(Radius.cardMac))
    }

    /// A checkbox and a row: either one toggles the repo.
    private func row(_ r: PickRepo) -> some View {
        let on = picked.contains(r.id)
        return ZStack(alignment: .leading) {
            CoreRow(r.name, subtitle: r.detail(now: now), selected: on) { toggle(r) }
                .padding(.leading, Space.s8)
            CoreCheckbox("", isOn: Binding(get: { on }, set: { _ in toggle(r) }))
                .padding(.leading, Space.s3).accessibilityHidden(true)
        }
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
