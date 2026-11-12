import CoreUI
import SwiftUI

/// Left column of the AI Sessions list (variant B): what needs attention, when, projects, runners.
struct SessionSidebar: View {
    @Bindable var model: AgentsModel
    let index: SessionIndex
    @Environment(\.corePalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s1) {
                heading("Needs attention")
                item("Active", .active, hot: false)
                item("Needs you", .needsYou, hot: true)
                item("Running", .running)
                item("Waiting for you", .waiting)
                item("Pinned", .pinned)
                heading("When")
                item("Today", .today)
                item("Yesterday", .yesterday)
                item("This week", .thisWeek)
                item("Earlier", .earlier)
                item("Archive", .archive)
                if !index.projects.isEmpty {
                    heading("Projects")
                    ForEach(index.projects, id: \.name) { p in
                        item(p.name, .project(p.name), count: p.count)
                    }
                }
                if !index.runners.isEmpty {
                    heading("Runners")
                    ForEach(index.runners, id: \.id) { r in
                        item(model.runnerName(r.id), .runner(r.id), count: r.count)
                    }
                }
            }
            .padding(.vertical, Space.s1)
        }
        .scrollIndicators(.never)
        .accessibilityLabel("AI session groups")
    }

    private func heading(_ t: String) -> some View {
        Text(t).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(palette.text2)
            .padding(.horizontal, Space.s3).padding(.top, Space.s3).padding(.bottom, Space.s1)
            .accessibilityAddTraits(.isHeader)
    }

    private func item(_ title: String, _ scope: SessionScope, hot: Bool = false, count: Int? = nil) -> some View {
        let n = count ?? index.counts[scope] ?? 0
        return SidebarItem(title: title, count: n, hot: hot, on: model.scope == scope) { model.scope = scope }
    }
}

/// One sidebar entry: the name and its count; hover lightens it, the chosen one is a lifted well with an edge.
private struct SidebarItem: View {
    let title: String
    let count: Int
    let hot: Bool
    let on: Bool
    let pick: () -> Void
    @Environment(\.corePalette) private var palette

    var body: some View {
        Button(action: pick) {
            HStack(spacing: Space.s2) {
                Text(title).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: Space.s2)
                CountBadge(count, tone: hot && count > 0 ? .needsYou : .quiet, showsZero: true)
            }
            .coreFont(size: MacTextSize.body)
            .padding(.horizontal, Space.s3).frame(minHeight: MacSize.controlLg)
            .contentShape(Rectangle())
        }
        .buttonStyle(CoreQuietPressStyle(radius: Radius.control, scale: 0.99, hoverFill: true))
        .clipShape(coreShape(Radius.control))
        .background { if on { Color.clear.coreWell(radius: Radius.control, active: true) } }
        .foregroundStyle(on ? palette.text : palette.text2)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Column widths shared by the header and every row so they line up.
enum SessionColumns {
    static let runner: CGFloat = 150
    static let state: CGFloat = 128
    static let activity: CGFloat = 96
    static let cost: CGFloat = 64
}

/// One dense row: tool tile, title and project, runner, state, last activity, cost. P pins and E ends from the keyboard; the
/// same two show as buttons on the selected or hovered row.
struct SessionRow: View {
    let session: AgentSessionInfo
    let title: String
    let runner: String
    let waiting: Bool
    let pinned: Bool
    let selected: Bool
    let compact: Bool
    let now: Date
    let onPin: () -> Void
    let onEnd: () -> Void
    @State private var hover = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        let st = AgentWords.status(session, waiting: waiting)
        let hue = SessionTile.hue(session.harness)
        HStack(spacing: Space.s3) {
            Image(systemName: AgentsModel.harnessSymbol(session.harness))
                .coreFont(size: MacTextSize.meta, weight: .semibold)
                .foregroundStyle(palette.btnInk).frame(width: MacSize.controlSm, height: MacSize.controlSm)
                .background(hue, in: coreShape(Radius.chip)).accessibilityHidden(true)
            HStack(spacing: Space.s2) {
                if pinned {
                    Image(systemName: "pin.fill").coreFont(size: MacTextSize.floor).foregroundStyle(palette.text2)
                }
                Text(title).coreFont(size: MacTextSize.body, weight: .medium).lineLimit(1).truncationMode(.tail)
                    .help(title)
                if let p = session.project {
                    Text(p).foregroundStyle(palette.text2).lineLimit(1).truncationMode(.tail).layoutPriority(-1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if hover || selected {
                HStack(spacing: Space.s1) {
                    mini(pinned ? "Unpin" : "Pin", "P", onPin)
                    if session.live { mini("End", "E", onEnd) }
                }
                .transition(.opacity)
            }
            if !compact {
                Text(runner).lineLimit(1).truncationMode(.tail)
                    .frame(width: SessionColumns.runner, alignment: .leading)
            }
            StateBadge(st.label, tone: st.tone, symbol: st.symbol).frame(
                width: SessionColumns.state, alignment: .leading)
            if !compact {
                Text(AgentWords.ago(session.updatedAt, now: now))
                    .frame(width: SessionColumns.activity, alignment: .leading)
            }
            Text(AgentWords.cost(session.usage?.costMicros) ?? "").monospacedDigit()
                .frame(width: SessionColumns.cost, alignment: .trailing)
                .help(AgentWords.exactCost(session.usage?.costMicros) ?? "")
        }
        .coreFont(size: MacTextSize.body)
        .padding(.horizontal, Space.s3).frame(height: Space.s8 + Space.s1)
        .background {
            if selected {
                Color.clear.coreWell(radius: Radius.control, active: true)
            } else if hover {
                coreShape(Radius.control).fill(palette.uDim)
            }
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .animation(Motion.out(Motion.hover), value: hover)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(AgentWords.toolName(session.harness)) on \(runner), \(st.label)")
    }

    private func mini(_ t: String, _ key: String, _ run: @escaping () -> Void) -> some View {
        Button(t, action: run).buttonStyle(CoreButtonStyle(.secondary, size: .small)).environment(\.coreKeycap, key)
            .help("\(t) (\(key))")
    }
}

/// A section's header: chevron, name, count, and what it cost in total at the right.
struct SectionHeader: View {
    let group: SessionGroup
    let collapsed: Bool
    let toggle: () -> Void
    @Environment(\.corePalette) private var palette

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Space.s2) {
                Image(systemName: "chevron.down").coreFont(size: MacTextSize.floor, weight: .semibold)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                    .frame(width: Space.s3)
                Text(group.section.title).coreFont(size: MacTextSize.body, weight: .semibold)
                    .foregroundStyle(group.section == .needsYou ? GlassInk.amberInk : palette.text)
                CountBadge(group.rows.count, tone: .quiet)
                Spacer()
                if let c = AgentWords.cost(group.costMicros), group.costMicros > 0 {
                    Text("\(c) in total").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                }
            }
            .foregroundStyle(palette.text2)
            .padding(.horizontal, Space.s3).frame(minHeight: MacSize.controlLg).contentShape(Rectangle())
        }
        .buttonStyle(CoreQuietPressStyle(radius: Radius.control, scale: 0.99, hoverFill: true))
        .clipShape(coreShape(Radius.control))
        .accessibilityLabel("\(group.section.title), \(group.rows.count)")
        .accessibilityValue(collapsed ? "collapsed" : "expanded")
    }
}
