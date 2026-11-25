import CoreUI
import SwiftUI

/// The map (Routes): the Core on the left, wired to each host the way it is really reached. A host behind a jump host is a
/// dashed second hop. The selected route is lit, with a pulse running along it (resting still under Reduce Motion). Hosts that
/// do not match the find field dim. More than `RouteLayout.bigFleet` hosts: `GroupsMap`.
struct RoutesMap: View {
    let model: LeylineModel

    // The grid of the map: the Core's card centre, a column per hop, the most a row may take.
    static let coreX: CGFloat = 116
    static let firstColumn: CGFloat = 470
    static let column: CGFloat = 360
    static let rowStep: CGFloat = 105
    static let half = CGSize(width: 88, height: 28)
    static let coreHalf: CGFloat = 96

    var body: some View {
        GeometryReader { geo in
            let hosts = model.fleet
            let place = RouteLayout.place(hosts)
            let rows = place.values.map(\.row)
            let lo = rows.min() ?? 0
            let span = (rows.max() ?? 0) - lo + 1
            let step = min(Self.rowStep, max(Space.s8 * 2, (geo.size.height - Space.s8) / max(span, 1)))
            let top = (geo.size.height - CGFloat(span) * step) / 2
            let points = place.mapValues {
                CGPoint(
                    x: Self.firstColumn + CGFloat($0.col) * Self.column, y: top + CGFloat($0.row - lo + 0.5) * step)
            }
            let firstYs = place.filter { $0.value.col == 0 }.compactMap { points[$0.key]?.y }
            let core = CGPoint(
                x: Self.coreX, y: firstYs.isEmpty ? geo.size.height / 2 : (firstYs.min()! + firstYs.max()!) / 2)
            let lines = wires(hosts, points, core)
            ZStack(alignment: .topLeading) {
                WireLayer(wires: lines)
                CoreNode(line: "\(Words.count(hosts.count, "host")) · \(model.onlineCount) online").position(core)
                ForEach(hosts) { h in
                    if let p = points[h.id] {
                        HostNode(model: model, host: h).position(p)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Map of routes")
        .accessibilityIdentifier("leyline-map")
    }

    private func wires(_ hosts: [HostItem], _ points: [String: CGPoint], _ core: CGPoint) -> [Wire] {
        let sel = model.selectedHost
        let lit = Set((sel.map { [$0.id] } ?? []) + (sel?.jumpChain ?? []))
        return hosts.compactMap { h in
            guard let to = points[h.id] else { return nil }
            let parent = h.jumpChain.last.flatMap { points[$0] }
            let from =
                parent.map { CGPoint(x: $0.x + Self.half.width, y: $0.y) }
                ?? CGPoint(x: core.x + Self.coreHalf, y: core.y)
            return Wire(
                from: from, to: CGPoint(x: to.x - Self.half.width, y: to.y), via: !h.jumpChain.isEmpty,
                hot: lit.contains(h.id), dim: !model.matches(h))
        }
    }
}

/// The big map: the Core wired to a card per group with its summary; only the open group's hosts spread out, as compact rows
/// in columns of eight. ← → move between groups, ↑ ↓ through the open group's hosts.
struct GroupsMap: View {
    let model: LeylineModel
    static let groupX: CGFloat = 380
    static let groupHalf: CGFloat = 105
    static let hostX: CGFloat = 760
    static let hostColumn: CGFloat = 200
    static let hostRow: CGFloat = 40
    static let miniHalf: CGFloat = 85

    var body: some View {
        GeometryReader { geo in
            let groups = model.mapGroups
            let step = min(120, max(Space.s8 * 2, (geo.size.height - Space.s8) / CGFloat(max(groups.count, 1))))
            let top = (geo.size.height - CGFloat(groups.count) * step) / 2 + step / 2
            let gy = { (i: Int) in top + CGFloat(i) * step }
            let core = CGPoint(
                x: RoutesMap.coreX, y: groups.isEmpty ? geo.size.height / 2 : (gy(0) + gy(groups.count - 1)) / 2)
            let open = model.currentGroup
            let oi = groups.firstIndex { $0.title == open } ?? 0
            let shown = groups.first { $0.title == open }?.hosts.filter(model.matches) ?? []
            let hy = { (r: Int) in Space.s8 + Space.s5 + CGFloat(r) * Self.hostRow }
            let wires: [Wire] =
                groups.enumerated().map { i, g in
                    Wire(
                        from: CGPoint(x: core.x + RoutesMap.coreHalf, y: core.y),
                        to: CGPoint(x: Self.groupX - Self.groupHalf, y: gy(i)), via: false, hot: g.title == open,
                        dim: !g.hosts.contains(where: model.matches))
                }
                + shown.prefix(RouteLayout.groupRows).enumerated().map { r, h in
                    Wire(
                        from: CGPoint(x: Self.groupX + Self.groupHalf, y: gy(oi)),
                        to: CGPoint(x: Self.hostX - Self.miniHalf, y: hy(r)), via: !h.jumpChain.isEmpty,
                        hot: h.id == model.selected, dim: false)
                }
            ZStack(alignment: .topLeading) {
                WireLayer(wires: wires)
                CoreNode(line: Words.count(model.fleet.count, "host")).position(core)
                ForEach(Array(groups.enumerated()), id: \.element.id) { i, g in
                    GroupNode(model: model, group: g, open: g.title == open).position(x: Self.groupX, y: gy(i))
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, h in
                    MiniHost(model: model, host: h)
                        .position(
                            x: Self.hostX + CGFloat(i / RouteLayout.groupRows) * Self.hostColumn,
                            y: hy(i % RouteLayout.groupRows)
                        )
                        .transition(.opacity)
                }
            }
            .animation(Motion.out(Motion.ui), value: open)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Map of groups")
        .accessibilityIdentifier("leyline-map")
    }
}

// MARK: wires

/// One wire: a smooth S from the right edge of one card to the left edge of the next.
struct Wire: Equatable {
    var from: CGPoint
    var to: CGPoint
    var via: Bool
    var hot: Bool
    var dim: Bool

    var path: Path {
        var p = Path()
        p.move(to: from)
        let mx = (from.x + to.x) / 2
        p.addCurve(to: to, control1: CGPoint(x: mx, y: from.y), control2: CGPoint(x: mx, y: to.y))
        return p
    }

    /// The point a share `t` along the curve.
    func point(_ t: CGFloat) -> CGPoint {
        let mx = (from.x + to.x) / 2
        let u = 1 - t
        let a = u * u * u
        let b = 3 * u * u * t
        let c = 3 * u * t * t
        let d = t * t * t
        return CGPoint(
            x: a * from.x + b * mx + c * mx + d * to.x, y: a * from.y + b * from.y + c * to.y + d * to.y)
    }
}

/// Every wire, and a pulse running along each lit one: 1.6 s from start to end, fading in and out at the ends. Reduce
/// Motion: the pulse rests in the middle of the wire.
struct WireLayer: View {
    let wires: [Wire]
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        ZStack {
            Canvas { ctx, _ in
                for w in wires.sorted(by: { !$0.hot && $1.hot }) {
                    let ink = w.hot ? palette.primary.opacity(0.95) : GlassInk.secondary.opacity(w.dim ? 0.12 : 0.35)
                    let dash: [CGFloat] = w.via && !w.hot ? [3, 5] : []
                    ctx.stroke(w.path, with: .color(ink), style: StrokeStyle(lineWidth: w.hot ? 1.6 : 1.4, dash: dash))
                }
            }
            TimelineView(.animation(paused: reduce)) { tl in
                let t = reduce ? 0.5 : tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                Canvas { ctx, _ in
                    let fade = reduce ? 1 : min(1, min(t, 1 - t) / 0.2)
                    for w in wires where w.hot {
                        let p = w.point(CGFloat(t))
                        let r = CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)
                        ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(palette.primary.opacity(fade)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: cards

/// "Your Core": where every route starts.
struct CoreNode: View {
    let line: String
    var body: some View {
        HStack(spacing: Space.s3) {
            CoreEmblemTile()
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Core").coreFont(size: MacTextSize.body, weight: .semibold)
                HStack(spacing: Space.s1 + 2) {
                    StatusLight(light: .ok)
                    Text(line).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
            }
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// A host on the small map: its tile, name, light and answer time, its group; a badge when AI waits for a person. Click
/// selects, double-click opens the terminal.
struct HostNode: View {
    let model: LeylineModel
    let host: HostItem
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let sel = model.selected == host.id
        HStack(spacing: Space.s2 + 2) {
            HostTile(symbol: host.symbol(isJump: model.jumpIDs.contains(host.id)))
            VStack(alignment: .leading, spacing: 2) {
                Text(host.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                HStack(spacing: Space.s1 + 2) {
                    StatusLight(light: host.light)
                    Text(([host.latencyWord ?? "not checked"] + [model.groupTitle(host)]).joined(separator: " · "))
                        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2 + 2)
        .frame(width: RoutesMap.half.width * 2)
        .modifier(SelectedFill(selected: sel, hover: hover, radius: Radius.cardMac))
        .overlay(alignment: .topTrailing) {
            if model.extras[host.id]?.approval != nil {
                CountBadge(1, label: "AI waits for you").offset(x: Space.s1 + 2, y: -(Space.s1 + 2))
            }
        }
        .scaleEffect(sel && !reduce ? 1.04 : 1)
        .opacity(model.matches(host) ? 1 : 0.28)
        .contentShape(coreShape(Radius.cardMac))
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { model.openHost(host.id) }
        .onTapGesture { model.select(host.id) }
        .animation(Motion.out(Motion.ui), value: sel)
        .animation(Motion.out(Motion.hover), value: hover)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(sel ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("host-node-\(host.name)")
    }
}

/// A group on the big map: its name and "14 hosts · 2 slow · 1 offline", with a badge when AI waits on one of them.
struct GroupNode: View {
    let model: LeylineModel
    let group: HostGroup
    let open: Bool
    @State private var hover = false

    var body: some View {
        let sum = GroupSummary(group.hosts, approvals: model.approvalIDs)
        HStack(spacing: Space.s2 + 2) {
            HostTile(symbol: "folder")
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                SummaryLine(summary: sum)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2 + 2)
        .frame(width: GroupsMap.groupHalf * 2)
        .modifier(SelectedFill(selected: open, hover: hover, radius: Radius.cardMac))
        .opacity(group.hosts.contains(where: model.matches) ? 1 : 0.28)
        .contentShape(coreShape(Radius.cardMac))
        .onHover { hover = $0 }
        .onTapGesture { model.showGroup(group.title) }
        .animation(Motion.out(Motion.hover), value: hover)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(open ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("group-node-\(group.title)")
    }
}

/// "12 hosts", "1 slow", "1 offline", each with its light, and the approvals badge.
struct SummaryLine: View {
    let summary: GroupSummary
    var body: some View {
        HStack(spacing: Space.s2) {
            Text("\(summary.hosts) host\(summary.hosts == 1 ? "" : "s")")
            if summary.slow > 0 {
                HStack(spacing: Space.s1) {
                    StatusLight(light: .slow)
                    Text("\(summary.slow) slow")
                }
            }
            if summary.offline > 0 {
                HStack(spacing: Space.s1) {
                    StatusLight(light: .off)
                    Text("\(summary.offline) offline")
                }
            }
            if summary.approvals > 0 { CountBadge(summary.approvals, label: "AI requests wait for you") }
        }
        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary.words.joined(separator: ", "))
    }
}

/// A host of the open group on the big map: a compact row.
struct MiniHost: View {
    let model: LeylineModel
    let host: HostItem
    @State private var hover = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        let sel = model.selected == host.id
        let via = host.jumpChain.last.flatMap { model.hostItem($0)?.name }
        HStack(spacing: Space.s2) {
            StatusLight(light: host.light)
            Text(host.name).coreFont(size: MacTextSize.body, weight: sel ? .semibold : .regular).lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(sel ? palette.primary : GlassInk.primary)
            Spacer(minLength: Space.s1)
            Text(([via.map { "via \($0)" }, host.latencyWord].compactMap { $0 }).joined(separator: " · "))
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, Space.s2 + 2)
        .frame(width: GroupsMap.miniHalf * 2, height: Space.s6 + Space.s1 + 2)
        .modifier(SelectedFill(selected: sel, hover: hover, radius: Radius.control))
        .contentShape(coreShape(Radius.control))
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { model.openHost(host.id) }
        .onTapGesture { model.select(host.id) }
        .animation(Motion.out(Motion.hover), value: hover)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(sel ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("host-mini-\(host.name)")
    }
}
