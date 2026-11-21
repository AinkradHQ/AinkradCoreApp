import CoreUI
import Shell
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
/// A fresh Brain (nothing in any area) leads with Import.
private struct CalmHome: View {
    let brain: BrainModel
    private var calm: BrainCalmModel { brain.calm }

    /// Nothing learned anywhere yet.
    private var fresh: Bool {
        calm.areas != nil && nodes.allSatisfy { $0.count == 0 } && calm.learned.isEmpty && calm.autoImports.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            header
            HStack(alignment: .top, spacing: Space.s6) {
                map.frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: Space.s3) {
                    if fresh && brain.importGlance == nil {
                        TeachCard(brain: brain)
                    } else {
                        DoingNow(brain: brain)
                        Learned(brain: brain)
                    }
                    HStack(alignment: .top, spacing: Space.s2) {
                        Image(systemName: "lock").accessibilityHidden(true)
                        Text("Every place is its own room. What Brain learns in one never leaks into another.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .padding(.horizontal, Space.s2)
                    Spacer(minLength: 0)
                }
                .frame(width: Space.s8 * 12)
                .padding(.top, fresh ? Space.s8 * 3 : 0)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Brain").coreFont(size: MacTextSize.title, weight: .semibold)
                Text(fresh ? "Empty for now" : "What it knows about you and your work, kept up by itself")
                    .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: Space.s3)
            Button {
                brain.openImport()
            } label: {
                Label(brain.importGlance == nil ? "Import…" : "Open import", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(CoreButtonStyle(.secondary))
            .keyboardShortcut("i", modifiers: .command).environment(\.coreKeycap, "⌘I")
            .accessibilityIdentifier("brain-home-import")
            Button {
                brain.explore(true)
            } label: {
                Label("Explore", systemImage: "magnifyingglass")
            }
            .buttonStyle(CoreButtonStyle(.secondary))
            .keyboardShortcut("e", modifiers: .command).environment(\.coreKeycap, "⌘E")
            .accessibilityIdentifier("brain-home-explore")
        }
    }

    private var nodes: [RadialNode] {
        func n(_ p: BrainCalmModel.Page) -> RadialNode {
            let s = p.area.flatMap { calm.summary($0) }
            let count = s?.count ?? (p == .places ? calm.areas?.places ?? 0 : 0)
            return RadialNode(
                page: p, count: count,
                line: s?.latest ?? (p == .places && count > 0 ? "Every place is its own room" : "Nothing yet"),
                today: s?.today ?? 0)
        }
        return [.me, .rules, .knowledge, .timeline, .places].map(n)
    }

    private var map: some View {
        RadialMap(
            nodes: nodes, working: brain.topChip?.state == "working",
            label: brain.status.chip?.state == "needs_you" ? "Paused" : "Learning 24/7"
        ) { p in Task { await calm.open(p) } }
    }
}

/// A fresh Brain: one card that says what Import does, with Import as the main action (mockup 15, empty).
private struct TeachCard: View {
    let brain: BrainModel
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Image(systemName: "square.and.arrow.down").coreFont(size: MacTextSize.title)
                .frame(width: Space.s8 + Space.s4, height: Space.s8 + Space.s4)
                .background(GlassInk.well, in: coreShape(Radius.control))
                .accessibilityHidden(true)
            Text("Teach Brain about your work").coreFont(size: MacTextSize.title, weight: .semibold)
            Text(
                "Bring in your past sessions and notes once. Brain sorts and learns them by itself, then keeps going on its own."
            )
            .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Button {
                brain.openImport()
            } label: {
                Label("Import my work", systemImage: "arrow.right")
            }
            .buttonStyle(CoreButtonStyle(.prominent))
            .coreShortcut(.primary)
            .accessibilityIdentifier("brain-teach-import")
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).coreWell()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-teach")
    }
}

/// "Doing now": an import under way first (with its progress and Open), else the Core's own line, with a bar only while
/// it works.
private struct DoingNow: View {
    let brain: BrainModel
    var body: some View {
        let chip = brain.status.chip
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("Doing now").coreFont(size: MacTextSize.headline, weight: .semibold)
                Spacer()
                if brain.importGlance != nil || chip?.state == "working" {
                    StateBadge("Awake", tone: .done, symbol: "sparkles")
                } else if let chip, chip.state != "needs_you" {
                    StateBadge("Resting", tone: .queue, symbol: "moon.zzz")
                }
            }
            if let i = brain.importGlance {
                importing(i)
            } else if let chip, chip.state == "needs_you" || chip.state == "locked" {
                // The only ask Brain makes (E9-5).
                Text(chip.needs.first ?? chip.line).coreFont(size: MacTextSize.body, weight: .semibold)
                Text("It cannot learn new things without it.").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
            } else {
                Text(chip?.line ?? "Waiting for the Core").coreFont(size: MacTextSize.body)
                    .fixedSize(horizontal: false, vertical: true)
                if chip?.state == "working" { CoreBusyBar().accessibilityHidden(true) }
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).coreWell()
        .accessibilityIdentifier("brain-doing-now")
    }

    @ViewBuilder private func importing(_ i: BrainGlance.Importing) -> some View {
        Text("Importing your work").coreFont(size: MacTextSize.headline, weight: .semibold)
        if let p = i.progress {
            CoreMeter(p, label: "Import progress")
        } else {
            CoreBusyBar().accessibilityHidden(true)
        }
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text("\(i.step) · \(i.line)\(i.detail.map { " · \($0)" } ?? "")")
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.s2)
            Button("Open") { brain.openImport() }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                .accessibilityIdentifier("brain-doing-open-import")
        }
        .accessibilityIdentifier("brain-doing-import")
    }
}

/// "What I learned today": what Brain saved by itself and the imports it accepted, each with Undo. The newest few; the rest
/// are in Explore.
private struct Learned: View {
    let brain: BrainModel
    @Environment(\.accessibilityReduceMotion) private var reduce
    private static let shown = 4

    var body: some View {
        let calm = brain.calm
        let rows = Array(calm.learned.prefix(max(0, Self.shown - calm.autoImports.count)))
        let more = calm.learned.count - rows.count
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("What I learned today").coreFont(size: MacTextSize.headline, weight: .semibold)
                .foregroundStyle(GlassInk.secondary)
            if calm.learned.isEmpty && calm.autoImports.isEmpty {
                Text("Nothing new yet. It keeps watching.").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
            }
            ForEach(calm.autoImports) { a in
                row(
                    "Sorted your import into \(BrainWords.plural(a.rooms, "place", "places"))", "Places · Import",
                    symbol: "folder"
                ) { await calm.undoImport(a) }
            }
            ForEach(rows) { l in
                row(l.line, l.at.isEmpty ? l.areaTitle : "\(l.areaTitle) · \(l.at)", symbol: l.symbol) {
                    await calm.undo(l)
                }
            }
            if more > 0 {
                Button("See all \(calm.learned.count) in Explore") { brain.explore(true, tab: .records) }
                    .buttonStyle(CoreButtonStyle(.plain, size: .small))
                    .accessibilityIdentifier("brain-learned-more")
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).coreWell()
        // Reduce Motion: the list changes at once, no fade.
        .animation(
            Motion.calm(Motion.out(Motion.ui), reduce), value: calm.learned.map(\.id) + calm.autoImports.map(\.run)
        )
        .accessibilityIdentifier("brain-learned")
    }

    /// One line of the mockup: the icon in a small well, the words in full (never cut), the area and time, Undo.
    private func row(_ line: String, _ sub: String, symbol: String, undo: @escaping () async -> Void) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: symbol).coreFont(size: MacTextSize.meta)
                .frame(width: Space.s6 + Space.s1, height: Space.s6 + Space.s1)
                .background(GlassInk.well, in: coreShape(Radius.chip))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(line).coreFont(size: MacTextSize.body).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await undo() }
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(CoreButtonStyle(.plain, size: .small))
            .help("Take this back. It is archived, never deleted.")
        }
        .accessibilityElement(children: .contain)
        .transition(.opacity)
    }
}
