import CoreUI
import SwiftUI

private let cardColumns = [GridItem(.adaptive(minimum: Space.s8 * 11), spacing: Space.s3, alignment: .top)]

/// Rooms: every room mounted on this Mac with its counts (names, mode, counts, health, no titles), the sealed ones as a
/// name and mode only, and one room's own view when you pick it.
struct RoomsTab: View {
    let model: BrainModel

    var body: some View {
        Group {
            if let id = model.inspectingID {
                RoomView(model: model, id: id)
            } else {
                list
            }
        }
        .animation(.smooth(duration: 0.25), value: model.inspectingID)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-rooms")
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s1) {
                BrainTitle("Rooms")
                Text("Each room is sealed apart from the others. Pick one to look at its numbers.")
                    .foregroundStyle(GlassInk.secondary)
            }
            LazyVGrid(columns: cardColumns, spacing: Space.s3) {
                ForEach(model.mountedRooms) { r in RoomCard(model: model, room: r) }
            }
            if !model.sealedRooms.isEmpty {
                BrainTitle("Sealed on this Mac")
                VStack(spacing: Space.s2) {
                    ForEach(model.sealedRooms) { r in SealedRow(model: model, room: r) }
                }
                Text("Sealed rooms show only their name and mode. Counts appear after you open them.")
                    .foregroundStyle(GlassInk.secondary)
            }
        }
    }
}

private struct RoomCard: View {
    let model: BrainModel
    let room: RoomSummary
    @State private var hovering = false
    var body: some View {
        let c = room.counts
        Button {
            Task { await model.inspect(room.id) }
        } label: {
            VStack(alignment: .leading, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    HStack(spacing: Space.s2) {
                        Text(room.name).font(.system(size: MacTextSize.title, weight: .semibold)).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Space.s2)
                        if room.id == model.viewingID { BrainChip("Viewing", GlassInk.blue) }
                    }
                    RoomChips(room: room)
                }
                Grid(alignment: .leading, horizontalSpacing: Space.s3, verticalSpacing: Space.s2) {
                    GridRow {
                        stat("Memories", c.map { $0.records.formatted() } ?? "—")
                        stat("Waiting", "\(c?.waiting ?? 0)")
                        stat("Conflicts", "\(c?.conflicts ?? 0)")
                    }
                    GridRow {
                        stat("Models", room.provider == .local ? "Local" : "\(c?.models ?? 0)")
                        stat("Last sync", c?.lastSync ?? "—")
                        stat(
                            "Key renews in", BrainWords.unit(room.lease.left),
                            hue: room.lease.state == .ok ? nil : GlassInk.blue)
                    }
                }
            }
            .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
            .coreWell(active: hovering || room.id == model.viewingID)
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain).focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: Motion.hover), value: hovering)
        .help(room.help)
        .accessibilityLabel("\(room.name), \(room.mode.label), \(room.provider.label), \((c?.records ?? 0)) memories")
    }

    private func stat(_ title: String, _ value: String, hue: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
            Text(value).font(.system(size: MacTextSize.body, weight: .medium)).monospacedDigit()
                .foregroundStyle(hue ?? GlassInk.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SealedRow: View {
    let model: BrainModel
    let room: RoomSummary
    var body: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "lock").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            Text(room.name).font(.system(size: MacTextSize.headline, weight: .semibold))
            RoomChips(room: room)
            Spacer(minLength: Space.s2)
            Button {
                Task { await model.open(room.id) }
            } label: {
                Label("Open with Touch ID", systemImage: "touchid")
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(model.busy != nil)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3).coreWell()
        .help(room.help)
        .accessibilityElement(children: .contain)
    }
}

/// One room's own view: exactly one room, in plain words, cleared the moment the viewing room changes.
private struct RoomView: View {
    let model: BrainModel
    let id: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Button {
                model.closeInspect()
            } label: {
                Label("All rooms", systemImage: "chevron.backward")
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            if let d = model.inspected, d.room.id == id {
                detail(d)
            } else if let r = model.room(id), let lock = r.lock {
                header(r)
                CoreNotice(symbol: "lock", title: lock.sentence, tone: .queue)
            } else {
                BrainSkeleton(shape: .page)
            }
        }
        .transition(.opacity)
    }

    private func header(_ r: RoomSummary) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(r.name).font(.system(size: MacTextSize.large, weight: .semibold))
                HStack(spacing: Space.s2) {
                    RoomChips(room: r)
                    BrainChip(
                        r.lock == nil ? "Open" : "Sealed", r.lock == nil ? GlassInk.green : GlassInk.slate)
                }
                Text(r.mode.story).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s3)
            if r.lock == nil {
                if r.id != model.viewingID {
                    Button("View this room") { model.view(r.id) }.buttonStyle(CoreButtonStyle(.prominent))
                }
                Button("Seal room") { Task { await model.seal(r.id) } }.buttonStyle(CoreButtonStyle(.secondary))
                    .disabled(model.busy != nil)
            } else {
                Button("Open with Touch ID") { Task { await model.open(r.id) } }
                    .buttonStyle(CoreButtonStyle(.prominent)).disabled(model.busy != nil)
            }
        }
        .padding(Space.s4).coreWell().help(r.help)
    }

    @ViewBuilder private func detail(_ d: RoomDetail) -> some View {
        header(d.room)
        if d.room.lease.state == .expiring {
            CoreNotice(
                symbol: "clock",
                title:
                    "The key renews in \(BrainWords.unit(d.room.lease.left)). Renew it before then, or the room seals.")
        }
        if let c = d.cost, c.capReached {
            CoreNotice(
                symbol: "dollarsign.circle",
                title: "Monthly cost cap reached. Meaning search is paused for this room; exact search still works.")
        }
        StatusBlock(status: d.status)
        HStack(alignment: .top, spacing: Space.s3) {
            BrainCard("Last sync, per device") {
                ForEach(d.sync) { row in
                    HStack {
                        Text(row.device)
                        Spacer(minLength: Space.s2)
                        Text(row.at).foregroundStyle(GlassInk.secondary)
                        BrainChip(
                            row.state == .ok ? "In step" : "Behind \(row.lag)",
                            row.state == .ok ? GlassInk.green : GlassInk.blue)
                    }
                    .padding(.vertical, 2)
                }
            }
            BrainCard(
                "Key renewal",
                sub: "Without renewal the saved copy on a device cannot be read. The technical word is lease."
            ) {
                Text(BrainWords.unit(d.room.lease.left)).font(.system(size: MacTextSize.large, weight: .semibold))
                    + Text(" left").foregroundStyle(GlassInk.secondary)
                BrainBar(
                    fraction: d.room.lease.fraction, hue: d.room.lease.state == .ok ? GlassInk.blue : GlassInk.orange)
                Text("Backup: \(d.backup ?? "none. This room never leaves this Mac.")").foregroundStyle(
                    GlassInk.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        if let c = d.cost { CostCard(cost: c) }
    }
}

private struct StatusBlock: View {
    let status: StatusCounts
    var body: some View {
        let items: [(String, Int, Color)] = [
            ("Waiting for you", status.candidate, GlassInk.blue), ("Active", status.active, GlassInk.blue),
            ("Replaced", status.superseded, GlassInk.slate), ("Archived", status.archived, GlassInk.slate),
            ("Removed", status.tombstoned, GlassInk.slate),
        ]
        BrainCard("Memories by status") {
            HStack(alignment: .top, spacing: Space.s5) {
                ForEach(items, id: \.0) { item in
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text(item.1.formatted()).font(.system(size: MacTextSize.large, weight: .semibold))
                            .monospacedDigit()
                        Text(item.0).foregroundStyle(GlassInk.secondary)
                        BrainBar(fraction: Double(item.1) / Double(max(status.total, 1)), hue: item.2, height: 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct CostCard: View {
    let cost: RoomCost
    var body: some View {
        BrainCard("Cost this month") {
            HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
                Text(cost.month.formatted(.currency(code: "USD"))).font(
                    .system(size: MacTextSize.large, weight: .semibold)
                )
                .monospacedDigit()
                Text("of \(cost.cap.formatted(.currency(code: "USD").precision(.fractionLength(0)))) cap")
                    .foregroundStyle(GlassInk.secondary)
            }
            BrainBar(
                fraction: cost.cap > 0 ? cost.month / cost.cap : 0, hue: cost.capReached ? GlassInk.red : GlassInk.blue,
                height: 4)
            let top = max(cost.series.max() ?? 1, 0.1)
            HStack(alignment: .bottom, spacing: Space.s1) {
                ForEach(Array(cost.series.enumerated()), id: \.offset) { _, v in
                    coreShape(3).fill(GlassInk.blue.opacity(0.6)).frame(height: Space.s8 * 2 * v / top)
                }
            }
            .frame(height: Space.s8 * 2, alignment: .bottom)
            .accessibilityHidden(true)
        }
    }
}
