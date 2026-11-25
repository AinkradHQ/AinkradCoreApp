import CoreUI
import SwiftUI

/// The list: a section per group with its summary, a row per host that matches the find field. ↑ ↓ move (and scroll),
/// Return opens the terminal. Room is left on the right for the host panel.
struct HostList: View {
    let model: LeylineModel

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4 + 2) {
                    ForEach(model.listGroups) { g in
                        VStack(alignment: .leading, spacing: Space.s1) {
                            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                                Text(g.title).coreFont(size: MacTextSize.title, weight: .semibold)
                                    .accessibilityAddTraits(.isHeader)
                                SummaryLine(
                                    summary: GroupSummary(
                                        model.fleet.filter { model.groupTitle($0) == g.title },
                                        approvals: model.approvalIDs))
                            }
                            .padding(.horizontal, Space.s1).padding(.bottom, Space.s1)
                            ForEach(g.hosts) { h in HostRow(model: model, host: h).id(h.id) }
                        }
                    }
                }
                .padding(.leading, Space.s5).padding(.trailing, HostPeek.width + Space.s8 + Space.s2)
                .padding(.bottom, Space.s4)
            }
            .scrollIndicators(.never)
            .onChange(of: model.selected) { _, id in
                guard let id else { return }
                withAnimation(Motion.out(Motion.ui)) { reader.scrollTo(id, anchor: nil) }
            }
        }
        .accessibilityIdentifier("leyline-list")
    }
}

/// One host in the list: tile, name and address, how it is reached, light and answer time, the answer-time line, CPU,
/// memory and disk as small bars, and a badge when AI waits. Each piece the Core does not send hides; the columns keep
/// their place so the rows still line up.
struct HostRow: View {
    let model: LeylineModel
    let host: HostItem
    @State private var hover = false

    var body: some View {
        let sel = model.selected == host.id
        let via = host.jumpChain.last.flatMap { model.hostItem($0)?.name }
        HStack(spacing: Space.s3 + 2) {
            HostTile(symbol: host.symbol(isJump: model.jumpIDs.contains(host.id)))
            VStack(alignment: .leading, spacing: 2) {
                Text(host.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                Text(host.login).coreFont(size: MacTextSize.meta, design: .monospaced)
                    .foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
            .frame(minWidth: Space.s8 * 4, maxWidth: .infinity, alignment: .leading)
            Group {
                if let via {
                    Label("via \(via)", systemImage: "checkmark.shield")
                } else {
                    Text(host.viaRunner == nil ? "Direct" : "Through a runner")
                }
            }
            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
            .frame(minWidth: Space.s8 * 3, maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Space.s1 + 2) {
                StatusLight(light: host.light)
                Text(host.latencyWord ?? "not checked").coreFont(size: MacTextSize.meta)
            }
            .frame(width: Space.s8 * 3, alignment: .leading)
            spark.frame(width: Space.s8 * 3, height: Space.s5)
            meters.frame(width: Space.s8 * 8, alignment: .leading)
            Group {
                if model.extras[host.id]?.approval != nil { CountBadge(1, label: "AI waits for you") }
            }
            .frame(width: Space.s6)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .modifier(SelectedFill(selected: sel, hover: hover, radius: Radius.row))
        .contentShape(coreShape(Radius.row))
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { model.openHost(host.id) }
        .onTapGesture { model.select(host.id) }
        .animation(Motion.out(Motion.hover), value: hover)
        .animation(Motion.out(Motion.ui), value: sel)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(sel ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("host-row-\(host.name)")
    }

    @ViewBuilder private var spark: some View {
        if host.light == .off {
            Text("offline").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let s = model.extras[host.id]?.latencyHistory, s.count > 1 {
            CoreSpark(s, ceiling: (s.max() ?? 1) * 1.2)
        } else {
            Color.clear
        }
    }

    @ViewBuilder private var meters: some View {
        if host.light == .off {
            Text(offLine).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
        } else if let h = model.healthByHost[host.id] {
            HStack(spacing: Space.s2) {
                ForEach([("CPU", h.cpuPct), ("Mem", h.memPct), ("Disk", h.diskPct)], id: \.0) { name, v in
                    if let v {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name).coreFont(size: 10).foregroundStyle(GlassInk.secondary)
                            LoadBar(percent: v)
                        }
                        .accessibilityElement()
                        .accessibilityLabel("\(name) \(Int(v.rounded())) percent")
                    }
                }
            }
        }
    }

    private var offLine: String {
        guard let d = host.reach?.seenAt else { return "Not answering" }
        return "No answer since \(d.formatted(date: .omitted, time: .shortened))"
    }
}
