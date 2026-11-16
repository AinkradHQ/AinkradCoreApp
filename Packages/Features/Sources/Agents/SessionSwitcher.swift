import CoreUI
import SwiftUI

/// The conversation's left sidebar (Ahmed, 2026-11-16): your other AI sessions, to switch in place. Shown or hidden with the
/// header's sidebar button or ⌃⌘S, remembered on this Mac. Pinned, Needs you and Running first, then the recent ones;
/// the full list (search, filters, archive) stays one click away in All sessions.
struct SessionSwitcher: View {
    @Bindable var model: AgentsModel
    let current: String
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    /// Recent sessions shown under the live ones.
    static let recent = 20

    @State private var filter = ""

    /// One line of the sidebar, flat (a lazy column does not redraw a list nested in its rows).
    private struct Item: Identifiable {
        let id: String
        let header: String?
        let session: AgentSessionInfo?
    }

    var body: some View {
        let index = model.makeIndex()
        let items = Self.items(Self.groups(index), filter: filter) { model.title($0) }
        let waiting = index.needsYou
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text("AI Sessions").coreFont(size: MacTextSize.body, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                CoreIconButton(symbol: "plus", label: "New AI session") { model.openNewSession() }
                    .help("Start a new AI session")
            }
            // Room at the left for the fixed sidebar toggle (SessionView), as in the mockup.
            .padding(.leading, Space.s8).padding(.trailing, Space.s2)
            filterField
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.s1) {
                    ForEach(items) { item in
                        if let h = item.header {
                            Text(h).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(palette.text2)
                                .padding(.horizontal, Space.s2).padding(.top, Space.s2)
                                .accessibilityAddTraits(.isHeader)
                        } else if let s = item.session {
                            row(s, waiting: waiting.contains(s.id))
                        }
                    }
                    if items.isEmpty {
                        Text(filter.isEmpty ? "No other sessions yet." : "No session matches “\(filter)”.")
                            .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                            .padding(Space.s2)
                    }
                }
                .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: items.map(\.id))
            }
            .scrollIndicators(.never)
            Button {
                model.openList()
            } label: {
                Label("All sessions", systemImage: "list.bullet").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(CoreButtonStyle(.plain, size: .medium))
            .help("Open the full list: search, filters and the archive")
        }
        .padding(Space.s2)
        .frame(maxHeight: .infinity, alignment: .top)
        .coreWell(radius: 12)  // follows the Appearance setting (Look)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Other AI sessions")
    }

    /// Narrows the sidebar by title as you type; Esc clears it.
    private var filterField: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "magnifyingglass").foregroundStyle(palette.text2).accessibilityHidden(true)
            TextField("Filter", text: $filter).textFieldStyle(.plain)
                .onExitCommand { filter = "" }
                .accessibilityLabel("Filter sessions")
            if !filter.isEmpty {
                CoreIconButton(symbol: "xmark", label: "Clear the filter") { filter = "" }
            }
        }
        .coreFont(size: MacTextSize.body)
        .padding(.horizontal, Space.s2).frame(minHeight: MacSize.controlMd)
        .background(SessionInk.field, in: coreShape(Radius.control))
    }

    /// The groups as flat lines, headers included; a filter keeps the sessions whose title holds it, and their headers.
    private static func items(
        _ groups: [SessionGroup], filter: String, title: (AgentSessionInfo) -> String
    ) -> [Item] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        var out: [Item] = []
        for g in groups {
            let rows = q.isEmpty ? g.rows : g.rows.filter { title($0).lowercased().contains(q) }
            guard !rows.isEmpty else { continue }
            out.append(
                Item(id: "h:\(g.section)", header: g.section == .earlier ? "Recent" : g.section.title, session: nil))
            out += rows.map { Item(id: $0.id, header: nil, session: $0) }
        }
        return out
    }

    private func row(_ s: AgentSessionInfo, waiting: Bool) -> some View {
        let on = s.id == current
        let st = AgentWords.status(s, waiting: waiting)
        return Button {
            model.switchSession(from: current, to: s.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                // A small square in the state's colour; the state's name is in the tooltip and for VoiceOver.
                coreShape(2).fill(palette.tone(st.tone).ink).frame(width: 6, height: 6)
                    .alignmentGuide(.firstTextBaseline) { d in d[.bottom] }
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title(s)).coreFont(size: MacTextSize.body, weight: on ? .semibold : .regular)
                        .lineLimit(1).truncationMode(.tail)
                    // The state in words first, so it never rests on the square's colour alone.
                    Text([st.label, model.runnerName(s.runner), AgentWords.ago(s.updatedAt)].joined(separator: " · "))
                        .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s2).padding(.vertical, Space.s1 + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? SessionInk.selected : .clear, in: coreShape(Radius.control))
            .contentShape(Rectangle())
        }
        .buttonStyle(CoreQuietPressStyle(radius: Radius.control, scale: 0.99, hoverFill: true))
        // The first message becomes the title, as in the list (not "Claude · K9R011").
        .onAppear { model.loadTitle(s.id) }
        .help("\(model.title(s))\n\(st.label)")
        .accessibilityLabel("\(model.title(s)), \(st.label)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Pinned, Needs you and Running as the list groups them, then up to `recent` others, newest first.
    static func groups(_ index: SessionIndex) -> [SessionGroup] {
        var out = index.groups(scope: .active, filters: SessionFilters())
        let shown = Set(out.flatMap(\.rows).map(\.id))
        let others = [SessionScope.today, .yesterday, .thisWeek, .earlier]
            .flatMap { index.groups(scope: $0, filters: SessionFilters()).flatMap(\.rows) }
        var seen = shown
        let recent = others.filter { seen.insert($0.id).inserted }.sorted { $0.updatedAt > $1.updatedAt }
            .prefix(Self.recent)
        if !recent.isEmpty { out.append(SessionGroup(section: .earlier, rows: Array(recent))) }
        return out
    }
}
