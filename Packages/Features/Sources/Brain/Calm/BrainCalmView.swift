import CoreUI
import SwiftUI

/// The calm Brain (mockup 15): a sidebar of the areas and, beside it, the home map or one area. Explore is the full console.
struct BrainCalmView: View {
    let brain: BrainModel
    var calm: BrainCalmModel { brain.calm }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            CalmSide(brain: brain)
            VStack(alignment: .leading, spacing: Space.s4) {
                if let n = calm.notice {
                    CoreNotice(symbol: "exclamationmark.triangle", title: n, tone: .fail) { EmptyView() }
                }
                Group {
                    switch calm.page {
                    case .home: CalmHome(brain: brain)
                    case .places: CalmPlaces(brain: brain)
                    default: CalmArea(brain: brain)
                    }
                }
                .id(calm.page)
                .transition(.opacity)
            }
            .padding(.horizontal, Space.s6).padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .animation(Motion.out(Motion.ui), value: calm.page)
        .task { await calm.reload() }
        .accessibilityIdentifier("brain-calm")
    }
}

private struct CalmSide: View {
    let brain: BrainModel
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(BrainCalmModel.Page.allCases, id: \.self) { p in
                CoreRow(p.title, symbol: p.symbol, selected: brain.calm.page == p) {
                    Task { await brain.calm.open(p) }
                }
                .accessibilityIdentifier("brain-area-\(p.rawValue)")
            }
            Spacer(minLength: Space.s4)
            Button {
                brain.explore(true)
            } label: {
                Label("Explore everything", systemImage: "magnifyingglass")
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            .accessibilityIdentifier("brain-explore")
        }
        .padding(Space.s3)
        .frame(width: Space.s8 * 7)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The home map: the five areas around the Brain, live counts, and on the right what it is doing and what it learned.
private struct CalmHome: View {
    let brain: BrainModel
    private var calm: BrainCalmModel { brain.calm }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            header
            HStack(alignment: .top, spacing: Space.s6) {
                map.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: Space.s3) {
                    DoingNow(brain: brain)
                    Learned(brain: brain)
                    HStack(alignment: .top, spacing: Space.s2) {
                        Image(systemName: "lock").accessibilityHidden(true)
                        Text("Every place is its own room. What Brain learns in one never leaks into another.")
                    }
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
                .frame(width: Space.s8 * 12)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Brain").coreFont(size: MacTextSize.title, weight: .semibold)
            Text("What it knows about you and your work, kept up by itself")
                .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
        }
    }

    private var nodes: [RadialNode] {
        func n(_ p: BrainCalmModel.Page) -> RadialNode {
            let s = p.area.flatMap { calm.summary($0) }
            return RadialNode(
                page: p, count: s?.count ?? (p == .places ? calm.areas?.places ?? 0 : 0),
                line: s?.latest ?? (p == .places ? "Every place is its own room" : "Nothing yet"), today: s?.today ?? 0)
        }
        return [.me, .rules, .knowledge, .timeline, .places].map(n)
    }

    private var map: some View {
        RadialMap(
            nodes: nodes, working: brain.status.chip?.state == "working",
            label: brain.status.chip?.state == "needs_you" ? "Paused" : "Learning 24/7"
        ) { p in Task { await calm.open(p) } }
    }
}

/// "Doing now": the Core's own line, calm, with a bar only while it works.
private struct DoingNow: View {
    let brain: BrainModel
    var body: some View {
        let chip = brain.status.chip
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("Doing now").coreFont(size: MacTextSize.headline, weight: .semibold)
                Spacer()
                if let chip, chip.state != "needs_you" {
                    StateBadge(chip.state == "working" ? "Awake" : "Resting", tone: .done, symbol: "moon.zzz")
                }
            }
            if let chip, chip.state == "needs_you" || chip.state == "locked" {
                // The only ask Brain makes (E9-5).
                Text(chip.needs.first ?? chip.line).coreFont(size: MacTextSize.body, weight: .semibold)
                Text("It cannot learn new things without it.").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
            } else {
                Text(chip?.line ?? "Waiting for the Core").coreFont(size: MacTextSize.body)
                if chip?.state == "working" { CoreBusyBar().accessibilityHidden(true) }
            }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).coreWell()
        .accessibilityIdentifier("brain-doing-now")
    }
}

/// "What I learned today": what Brain saved by itself and the imports it accepted, each with Undo.
private struct Learned: View {
    let brain: BrainModel
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        let calm = brain.calm
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("What I learned today").coreFont(size: MacTextSize.headline, weight: .semibold)
            if calm.learned.isEmpty && calm.autoImports.isEmpty {
                Text("Nothing new yet. It keeps watching.").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
            }
            ForEach(calm.autoImports) { a in
                CoreRow(
                    "Sorted your import into \(BrainWords.plural(a.rooms, "place", "places"))", subtitle: "Import",
                    symbol: "folder"
                ) {
                    Button("Undo") { Task { await calm.undoImport(a) } }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
                .transition(.opacity)
            }
            ForEach(calm.learned) { l in
                CoreRow(l.line, subtitle: "\(l.roomName) · \(l.at)", symbol: l.symbol) {
                    HStack(spacing: Space.s2) {
                        StateBadge(l.areaTitle, tone: .done, symbol: l.symbol)
                        Button("Undo") { Task { await calm.undo(l) } }
                            .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).coreWell()
        // Reduce Motion: the list changes at once, no fade.
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: calm.learned.map(\.id) + calm.autoImports.map(\.run))
        .accessibilityIdentifier("brain-learned")
    }
}
