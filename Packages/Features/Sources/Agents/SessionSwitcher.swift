import CoreUI
import SwiftUI

/// The conversation's left sidebar (Ahmed, 2026-11-16): your other AI sessions, to switch in place. Shown or hidden with the
/// header's sidebar button or ⌃⌘S, remembered on this Mac. Pinned, Needs you and Running first, then the recent ones;
/// the full list (search, filters, archive) stays one click away in All sessions.
struct SessionSwitcher: View {
    @Bindable var model: AgentsModel
    let current: String
    @Environment(\.corePalette) private var palette

    /// Recent sessions shown under the live ones.
    static let recent = 20

    var body: some View {
        let groups = Self.groups(model.makeIndex())
        let waiting = model.makeIndex().needsYou
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text("AI Sessions").coreFont(size: MacTextSize.body, weight: .semibold).accessibilityAddTraits(
                    .isHeader)
                Spacer(minLength: 0)
                CoreIconButton(symbol: "plus", label: "New AI session") { model.openNewSession() }
                    .help("Start a new AI session")
            }
            .padding(.horizontal, Space.s2)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.s1) {
                    ForEach(groups) { g in
                        Text(g.section == .earlier ? "Recent" : g.section.title)
                            .coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(palette.text2)
                            .padding(.horizontal, Space.s2).padding(.top, Space.s2)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(g.rows) { s in
                            row(s, waiting: waiting.contains(s.id))
                        }
                    }
                }
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
        .coreWell()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Other AI sessions")
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
                    Text(model.runnerName(s.runner) + " · " + AgentWords.ago(s.updatedAt))
                        .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s2).padding(.vertical, Space.s1 + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? GlassInk.wellHover : .clear, in: coreShape(Radius.control))
            .contentShape(Rectangle())
        }
        .buttonStyle(CoreQuietPressStyle(radius: Radius.control, scale: 0.99, hoverFill: true))
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
