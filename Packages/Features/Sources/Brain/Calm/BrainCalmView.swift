import CoreUI
import Shell
import SwiftUI

/// Brain Home (Designs/core/0-10/review/brain, Home): the live map of sources, Brain and the four areas; what to check;
/// the four area cards with their last two weeks; what it learned today with Forget; and where it knows most.
/// A fresh Brain (nothing in any area) leads with Import.
struct CalmHome: View {
    let brain: BrainModel
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    private var calm: BrainCalmModel { brain.calm }

    /// Nothing learned anywhere yet.
    private var fresh: Bool {
        calm.areas != nil && Self.order.allSatisfy { (calm.summary($0.area ?? "")?.count ?? 0) == 0 }
            && calm.learned.isEmpty && calm.autoImports.isEmpty
    }

    static let order: [BrainCalmModel.Page] = [.knowledge, .rules, .timeline, .me]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                mapCard.coreRise(shown, 0)
                if let i = brain.importGlance {
                    ImportBanner(brain: brain, importing: i).coreRise(shown, 1)
                } else if fresh {
                    TeachCard(brain: brain).coreRise(shown, 1)
                }
                let checks = brain.checkQueue.count
                if checks > 0 { CheckBanner(brain: brain, count: checks).coreRise(shown, 1) }
                HStack(alignment: .top, spacing: Space.s4) {
                    ForEach(Array(Self.order.enumerated()), id: \.element) { i, p in
                        AreaCard(brain: brain, page: p).coreRise(shown, 2 + i)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: Space.s4) {
                    LearnedCard(brain: brain).frame(maxWidth: .infinity)
                    KnowsMostCard(brain: brain).frame(maxWidth: .infinity)
                }
                .coreRise(shown, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { shown = true }
        .accessibilityIdentifier("brain-home")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Brain").coreFont(size: MacTextSize.large, weight: .semibold).accessibilityAddTraits(.isHeader)
                Text(
                    fresh
                        ? "Empty for now. Import your past work and it learns by itself."
                        : "What it knows about you and your work. It learns by itself and never mixes one place with another."
                )
                .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: Space.s3)
            Button {
                brain.openImport()
            } label: {
                Label(brain.importGlance == nil ? "Import…" : "Open Import", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(CoreButtonStyle(.secondary))
            .environment(\.coreKeycap, "⌘I")
            .help("Import past sessions and notes (⌘I)")
            .accessibilityIdentifier("brain-home-import")
        }
    }

    // MARK: the map

    private var working: Bool { brain.topChip?.state == "working" }
    private var total: Int { Self.order.reduce(0) { $0 + (calm.summary($1.area ?? "")?.count ?? 0) } }
    private var learningPlace: String? { calm.places?.first { $0.learning && $0.room != "me" }?.name }

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(title).coreFont(size: MacTextSize.title, weight: .semibold).contentTransition(.opacity)
                Spacer(minLength: Space.s2)
                if working {
                    StateBadge("Learning", tone: .done, symbol: "sparkles")
                } else if brain.status.chip?.state == "needs_you" {
                    StateBadge("Paused", tone: .warn, symbol: "pause")
                } else {
                    StateBadge("Resting", tone: .queue, symbol: "moon")
                }
            }
            .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: working)
            BrainMap(
                sources: SourceGroup.make(brain.brainSources).prefix(3).map {
                    MapSource(id: $0.id, symbol: $0.symbol, title: $0.title, line: $0.mapLine, live: $0.reading)
                },
                shelves: Self.order.map { p in
                    let s = calm.summary(p.area ?? "")
                    return MapShelf(page: p, count: s?.count ?? 0, today: s?.today ?? 0)
                },
                working: working, line: centreLine
            ) { brain.go($0.tab) }
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coreWell()
    }

    private var title: String {
        if let chip = brain.status.chip, chip.state == "needs_you" || chip.state == "locked" {
            return chip.needs.first ?? chip.line
        }
        if working { return learningPlace.map { "Learning from \($0) right now" } ?? "Learning right now" }
        if total == 0 { return "Nothing learned yet" }
        return "Up to date · knows \(total.formatted()) things about your work"
    }

    /// Under the Brain: what it does now, else when it last learned something.
    private var centreLine: String {
        if let a = brain.status.activity, let line = BrainStatusModel.doing(a) { return line }
        if working, let i = brain.importGlance { return i.line }
        if let d = calm.learned.compactMap({ SyncWords.date($0.createdAt) }).max() {
            return "Last learned \(SyncWords.agoInLine(d))"
        }
        return "Nothing new today"
    }
}

/// An area's card: its count and what it took in today, what it means, the last two weeks as bars (API minor 101) and its
/// newest example. An empty About you says how it fills in.
private struct AreaCard: View {
    let brain: BrainModel
    let page: BrainCalmModel.Page
    @Environment(\.corePalette) private var palette
    @State private var hover = false

    var body: some View {
        let s = brain.calm.summary(page.area ?? "")
        let count = s?.count ?? 0
        Button {
            brain.go(page.tab)
        } label: {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    BrainTile(symbol: page.symbol, size: Space.s6)
                    Text(page.title).coreFont(size: MacTextSize.body, weight: .semibold)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary).opacity(hover ? 1 : 0.6).accessibilityHidden(true)
                }
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Text(count.formatted()).font(.system(size: 26, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(count == 0 ? GlassInk.secondary : GlassInk.primary)
                        .contentTransition(.numericText())
                    if let t = s?.today, t > 0 {
                        Text("+\(t.formatted()) today").coreFont(size: MacTextSize.body, weight: .semibold)
                            .foregroundStyle(palette.success)
                    }
                }
                Text(page.meaning).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                if let series = s?.series, count > 0 { DayBars(series: series).padding(.top, Space.s1) }
                if count == 0 {
                    Text(
                        "Nothing yet. It fills in as you work with AI sessions, from how you ask and what you correct."
                    )
                    .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, Space.s2)
                } else if let latest = s?.latest {
                    Text("“\(latest)”").coreFont(size: MacTextSize.body).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                        .background(GlassInk.well, in: coreShape(Radius.control))
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .coreWell(active: hover)
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Open \(page.title)")
        .accessibilityIdentifier("brain-node-\(page.rawValue)")
    }
}

/// "3 things to check": the banner that opens To check.
private struct CheckBanner: View {
    let brain: BrainModel
    let count: Int
    @Environment(\.coreAccent) private var accent

    var body: some View {
        let key = brain.sidebarTabs.firstIndex(of: .inbox).map { "⌘\($0 + 1)" }
        HStack(spacing: Space.s3) {
            BrainTile(symbol: "tray", lit: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(BrainWords.plural(count, "thing", "things")) to check")
                    .coreFont(size: MacTextSize.body, weight: .semibold).contentTransition(.numericText())
                Text("Brain is not sure about these. A quick yes or no keeps it right.")
                    .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: Space.s2)
            Button("Check Now") { brain.go(.inbox) }
                .buttonStyle(CoreButtonStyle(.prominent))
                .environment(\.coreKeycap, key)
                .help("Open To check\(key.map { " (\($0))" } ?? "")")
                .accessibilityIdentifier("brain-check-now")
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        .background(GlassInk.accent(accent).opacity(0.14), in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .contain)
    }
}

/// An import under way: its step, how far, and the way back into it.
private struct ImportBanner: View {
    let brain: BrainModel
    let importing: BrainGlance.Importing

    var body: some View {
        HStack(spacing: Space.s3) {
            BrainTile(symbol: "square.and.arrow.down", lit: true)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Importing your work · \(importing.line)").coreFont(size: MacTextSize.body, weight: .semibold)
                if let p = importing.progress {
                    CoreMeter(p, label: "Import progress")
                } else {
                    CoreBusyBar().accessibilityHidden(true)
                }
                if let d = importing.detail {
                    Text("\(importing.step) · \(d)").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary).monospacedDigit()
                }
            }
            Spacer(minLength: Space.s2)
            Button("Open Import") { brain.openImport() }.buttonStyle(CoreButtonStyle(.secondary))
                .accessibilityIdentifier("brain-doing-open-import")
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).coreWell()
        .accessibilityIdentifier("brain-doing-import")
    }
}

/// A fresh Brain: one card that says what Import does, with Import as the main action.
private struct TeachCard: View {
    let brain: BrainModel
    var body: some View {
        HStack(spacing: Space.s4) {
            BrainTile(symbol: "square.and.arrow.down", lit: true, size: Space.s8 + Space.s3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Teach Brain about your work").coreFont(size: MacTextSize.title, weight: .semibold)
                Text(
                    "Bring in your past sessions and notes once. Brain sorts and learns them by itself, then keeps going on its own."
                )
                .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s2)
            Button("Import My Work") { brain.openImport() }
                .buttonStyle(CoreButtonStyle(.prominent))
                .coreShortcut(.primary)
                .accessibilityIdentifier("brain-teach-import")
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).coreWell()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-teach")
    }
}
