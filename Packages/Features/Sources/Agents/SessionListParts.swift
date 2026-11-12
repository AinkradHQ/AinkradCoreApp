import CoreUI
import SwiftUI

/// Left column of the AI Sessions list (variant B): what needs attention, when, projects, runners.
struct SessionSidebar: View {
    @Bindable var model: AgentsModel
    let index: SessionIndex

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
        Text(t).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
            .padding(.horizontal, Space.s3).padding(.top, Space.s3).padding(.bottom, Space.s1)
    }

    private func item(_ title: String, _ scope: SessionScope, hot: Bool = false, count: Int? = nil) -> some View {
        let n = count ?? index.counts[scope] ?? 0
        let on = model.scope == scope
        return Button {
            model.scope = scope
        } label: {
            HStack(spacing: Space.s2) {
                Text(title).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: Space.s2)
                Text("\(n)").coreFont(size: MacTextSize.meta, weight: .semibold).monospacedDigit()
                    .padding(.horizontal, 6).frame(minWidth: 22, minHeight: 18)
                    .background(hot && n > 0 ? GlassInk.orange : GlassInk.well, in: coreShape(5))
                    .foregroundStyle(hot && n > 0 ? .black.opacity(0.8) : GlassInk.secondary)
            }
            .coreFont(size: MacTextSize.body)
            .padding(.horizontal, Space.s3).frame(height: 30)
            .background(on ? GlassInk.wellHover : .clear, in: coreShape(Radius.control))
            .overlay { if on { coreShape(Radius.control).strokeBorder(GlassInk.wellEdge, lineWidth: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(on ? GlassInk.primary : GlassInk.secondary)
        .accessibilityLabel("\(title), \(n)")
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

    var body: some View {
        let st = AgentWords.status(session, waiting: waiting)
        let hue = SessionTile.hue(session.harness)
        HStack(spacing: Space.s3) {
            Image(systemName: AgentsModel.harnessSymbol(session.harness)).coreFont(size: 11, weight: .semibold)
                .foregroundStyle(.white).frame(width: 22, height: 22)
                .background(hue, in: coreShape(6)).accessibilityHidden(true)
            HStack(spacing: Space.s2) {
                if pinned { Image(systemName: "pin.fill").coreFont(size: 10).foregroundStyle(GlassInk.secondary) }
                Text(title).coreFont(size: MacTextSize.body, weight: .medium).lineLimit(1).truncationMode(.tail)
                if let p = session.project {
                    Text(p).foregroundStyle(GlassInk.secondary).lineLimit(1).truncationMode(.tail).layoutPriority(-1)
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
                Text(runner).foregroundStyle(GlassInk.secondary).lineLimit(1).truncationMode(.tail)
                    .frame(width: SessionColumns.runner, alignment: .leading)
            }
            StateMark(label: st.label, session: session, waiting: waiting).frame(
                width: SessionColumns.state, alignment: .leading)
            if !compact {
                Text(AgentWords.ago(session.updatedAt, now: now)).foregroundStyle(GlassInk.secondary)
                    .frame(width: SessionColumns.activity, alignment: .leading)
            }
            Text(AgentWords.cost(session.usage?.costMicros) ?? "").monospacedDigit().foregroundStyle(GlassInk.secondary)
                .frame(width: SessionColumns.cost, alignment: .trailing)
                .help(AgentWords.exactCost(session.usage?.costMicros) ?? "")
        }
        .coreFont(size: MacTextSize.body)
        .padding(.horizontal, Space.s3).frame(height: 36)
        .background(selected ? GlassInk.wellHover : hover ? GlassInk.well : .clear, in: coreShape(Radius.control))
        .overlay { if selected { coreShape(Radius.control).strokeBorder(GlassInk.wellEdge, lineWidth: 1) } }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .animation(Motion.out(Motion.hover), value: hover)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(AgentWords.toolName(session.harness)) on \(runner), \(st.label)")
    }

    private func mini(_ t: String, _ key: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 4) {
                Text(t)
                Text(key).coreFont(size: 9, weight: .medium).padding(.horizontal, 4)
                    .background(.white.opacity(0.16), in: coreShape(3))
            }
            .coreFont(size: MacTextSize.meta).padding(.horizontal, Space.s2).frame(height: 22)
            .background(GlassInk.well, in: coreShape(5))
            .overlay { coreShape(5).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }
}

/// The state as a small rounded square and a word: orange Needs you, blue Running, green Waiting for you, quiet when ended.
struct StateMark: View {
    let label: String
    let session: AgentSessionInfo
    let waiting: Bool

    var body: some View {
        let hue: Color =
            waiting
            ? GlassInk.orange
            : session.idle
                ? GlassInk.green : session.live ? GlassInk.blue : session.state == .lost ? GlassInk.red : GlassInk.slate
        HStack(spacing: 6) {
            coreShape(2).fill(hue).frame(width: 7, height: 7)
            Text(label).lineLimit(1)
        }
        .coreFont(size: MacTextSize.meta, weight: .medium).foregroundStyle(GlassInk.ink(hue))
        .padding(.horizontal, Space.s2).frame(height: 22)
        .background(hue.opacity(0.18), in: coreShape(5))
    }
}

/// A section's header: chevron, name, count, and what it cost in total at the right.
struct SectionHeader: View {
    let group: SessionGroup
    let collapsed: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Space.s2) {
                Image(systemName: "chevron.down").coreFont(size: 9, weight: .semibold).rotationEffect(
                    .degrees(collapsed ? -90 : 0)
                )
                .frame(width: 12)
                Text(group.section.title).coreFont(size: MacTextSize.body, weight: .semibold)
                    .foregroundStyle(group.section == .needsYou ? GlassInk.orangeInk : GlassInk.primary)
                Text("\(group.rows.count)").coreFont(size: MacTextSize.meta).padding(.horizontal, 6)
                    .background(GlassInk.well, in: coreShape(4)).foregroundStyle(GlassInk.secondary)
                Spacer()
                if let c = AgentWords.cost(group.costMicros), group.costMicros > 0 {
                    Text("\(c) in total").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
            }
            .padding(.horizontal, Space.s3).frame(height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(group.section.title), \(group.rows.count)")
        .accessibilityValue(collapsed ? "collapsed" : "expanded")
    }
}
