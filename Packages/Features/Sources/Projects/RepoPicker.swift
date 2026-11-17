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
    var height: CGFloat = Space.s8 * 6 + Space.s2
    @State private var query = ""
    @FocusState private var searching: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            CoreFieldLabel(picked.isEmpty ? "Repos from GitHub" : "Repos from GitHub · \(picked.count) selected")
            HStack(spacing: Space.s2) {
                Image(systemName: "magnifyingglass").coreFont(size: MacTextSize.body, weight: .medium)
                    .foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                TextField(
                    "", text: $query,
                    prompt: Text("Search your repos or paste a link").foregroundStyle(GlassInk.secondary)
                )
                .textFieldStyle(.plain).focused($searching).onSubmit(addTypedLink)
                .accessibilityLabel("Search your repos or paste a link")
            }
            .padding(.horizontal, Space.s3).frame(height: MacSize.controlLg)
            .coreFieldSurface(focused: searching)
            list
        }
        .task { await model.loadCatalog() }
    }

    private var catalogState: RepoCatalogState { model.catalogState }
    private var now: Date { model.now() }

    /// The repos that match the search, by org then freshest first; pasted links sit in their own group.
    private var groups: [(org: String, repos: [PickRepo])] {
        var all: [PickRepo] = []
        if case .ready(let r) = catalogState { all = r }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let hit: (PickRepo) -> Bool = {
            q.isEmpty || $0.name.lowercased().contains(q) || $0.org.lowercased().contains(q)
        }
        let byOrg = Dictionary(grouping: all.filter(hit), by: \.org)
        var out = byOrg.keys.sorted().map { org in
            (org, byOrg[org]!.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) })
        }
        let mine = pasted.filter(hit)
        if !mine.isEmpty { out.append(("Pasted links", mine)) }
        return out
    }

    /// The search text, when it is a repo link that is not in the list yet.
    private var typedLink: PickRepo? {
        guard let r = ProjectRules.repo(fromLink: query) else { return nil }
        let known = pasted.contains { $0.url == r.url }
        if known { return nil }
        if case .ready(let all) = catalogState, all.contains(where: { $0.url == r.url }) { return nil }
        return PickRepo(org: "Pasted links", name: r.name, url: r.url)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s1) {
                if let link = typedLink {
                    row(link, detail: link.url, action: "Add link")
                }
                switch catalogState {
                case .loading:
                    ForEach(0..<3, id: \.self) { _ in CoreSkeleton(coreShape(Radius.control)).frame(height: 40) }
                case .unavailable where pasted.isEmpty && typedLink == nil:
                    Text("GitHub’s repo list is not available from this Core yet. Paste a repo link above to add one.")
                        .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                        .padding(Space.s2)
                case .ready where groups.isEmpty && typedLink == nil:
                    Text("No repo matches “\(query)”.").foregroundStyle(GlassInk.secondary).padding(Space.s2)
                default: EmptyView()
                }
                ForEach(groups, id: \.org) { g in
                    Text(g.org).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
                        .padding(.horizontal, Space.s2).padding(.top, Space.s2)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(g.repos) { r in row(r, detail: r.detail(now: now), action: nil) }
                }
            }
            .padding(Space.s1)
        }
        .scrollIndicators(.never)
        .frame(height: height)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .clipShape(coreShape(Radius.cardMac))
    }

    private func row(_ r: PickRepo, detail: String, action: String?) -> some View {
        let on = picked.contains(r.id)
        return Button {
            if action != nil { addTypedLink() } else { toggle(r) }
        } label: {
            HStack(spacing: Space.s2) {
                if action != nil {
                    Image(systemName: "plus").coreFont(size: MacTextSize.body, weight: .semibold)
                        .frame(width: 18, height: 18).accessibilityHidden(true)
                } else {
                    CoreCheckbox("", isOn: .constant(on)).allowsHitTesting(false).accessibilityHidden(true)
                        .frame(width: 18)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(action.map { "\($0): \(r.name)" } ?? r.name).lineLimit(1)
                    Text(detail).foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s2).padding(.vertical, Space.s1 + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? GlassInk.wellHover : .clear, in: coreShape(Radius.control))
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(r.name)
        .accessibilityValue(on ? "selected" : "not selected")
        .accessibilityHint(detail)
        .accessibilityAddTraits(on ? .isSelected : [])
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
