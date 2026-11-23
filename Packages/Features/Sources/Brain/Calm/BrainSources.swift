import CoreUI
import SwiftUI

/// What Brain reads from, as a person thinks of it: AI sessions, notes and docs, and each connection. One collector per
/// tool and machine stays under the switch of its group.
struct SourceGroup: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let sub: String
    let sources: [SourceWire]

    var enabled: Bool { sources.contains { $0.enabled } }
    /// Everything read: the Core's count (API minor 101), else the items delivered; nil when neither is known.
    var read: Int? {
        let t = sources.compactMap(\.readTotal)
        if !t.isEmpty { return t.reduce(0, +) }
        let i = sources.compactMap(\.items)
        return i.isEmpty ? nil : i.reduce(0, +)
    }
    /// API minor 101 only.
    var week: Int? {
        let w = sources.compactMap(\.readWeek)
        return w.isEmpty ? nil : w.reduce(0, +)
    }
    var last: Date? { sources.compactMap { SyncWords.date($0.lastReadAt ?? $0.lastRun) }.max() }
    var reading: Bool { sources.contains { $0.reading == true } }

    /// The line under its name on the home map.
    var mapLine: String {
        if reading { return "Reading now" }
        if !enabled { return "Off" }
        if let read { return "\(read.formatted()) read" }
        return last.map { "Read \(SyncWords.agoInLine($0))" } ?? "Not read yet"
    }

    static func make(_ all: [SourceWire]) -> [SourceGroup] {
        let sessions = all.filter { !$0.isConnection && SyncWords.group($0.kind) == SyncWords.sessionsGroup }
        let notes = all.filter { !$0.isConnection && SyncWords.group($0.kind) == SyncWords.notesGroup }
        var out: [SourceGroup] = []
        if !sessions.isEmpty {
            out.append(
                .init(
                    id: "sessions", symbol: "sparkles", title: "AI sessions",
                    sub: "Your AI sessions, on all your machines", sources: sessions))
        }
        if !notes.isEmpty {
            out.append(
                .init(
                    id: "notes", symbol: "folder", title: "Notes and docs",
                    sub: "Project docs, notes and chat exports", sources: notes))
        }
        for c in all where c.isConnection {
            let github = c.id == "github"
            out.append(
                .init(
                    id: c.id, symbol: github ? "globe" : "checklist", title: github ? "GitHub" : "Jira",
                    sub: github ? "Pull requests and reviews of your repositories" : "Issues of your projects",
                    sources: [c]))
        }
        return out
    }
}

extension BrainModel {
    /// The collectors the Sources page and the home map show.
    var brainSources: [SourceWire] {
        #if DEBUG
        if let d = calm.demoSources { return d }
        #endif
        return sync?.sources ?? []
    }

    /// One switch for a whole group: every collector in it on or off.
    func setSource(_ g: SourceGroup, on: Bool) {
        #if DEBUG
        if calm.demoSources != nil {
            calm.demoSources = calm.demoSources?.map { s in
                var s = s
                if g.sources.contains(where: { $0.id == s.id }) { s.enabled = on }
                return s
            }
            return
        }
        #endif
        guard let sync else { return }
        Task { for s in g.sources where s.enabled != on { await sync.toggle(s, on: on) } }
    }
}

/// Sources: one card per source with its switch, how much it read, this week and the last read; while it reads, a bar.
/// The detailed list of every collector and the rules for every room stay under More Details.
struct BrainSourcesPage: View {
    let brain: BrainModel
    @State private var details = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let groups = SourceGroup.make(brain.brainSources)
        VStack(alignment: .leading, spacing: Space.s4) {
            BrainHead(
                symbol: "square.and.arrow.down", title: "Sources",
                sub: "Where Brain reads from. Turn one off and it stops reading it; what it learned stays."
            ) {
                Button {
                    brain.openImport()
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(CoreButtonStyle(.secondary)).environment(\.coreKeycap, "⌘I")
                .help("Import past sessions and notes (⌘I)")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: Space.s4), GridItem(.flexible())],
                        alignment: .leading, spacing: Space.s4
                    ) {
                        ForEach(groups) { card($0) }
                        addCard
                    }
                    if let sync = brain.sync {
                        Button {
                            withAnimation(Motion.calm(Motion.out(Motion.ui), reduce)) { details.toggle() }
                        } label: {
                            Label("More Details", systemImage: details ? "chevron.down" : "chevron.right")
                        }
                        .buttonStyle(CoreButtonStyle(.plain, size: .small))
                        .help("Every collector on every machine, the rules for every place, and what Brain read")
                        if details {
                            SyncBannerView(brain: brain, sync: sync)
                            SourcesTab(brain: brain, sync: sync).transition(.opacity)
                            Text("What Brain read").coreFont(size: MacTextSize.headline, weight: .semibold)
                                .accessibilityAddTraits(.isHeader)
                            ExploreEvidenceTab(brain: brain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("brain-sources-page")
    }

    private func card(_ g: SourceGroup) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .center, spacing: Space.s3) {
                BrainTile(symbol: g.symbol, lit: g.enabled, size: Space.s8 + Space.s1)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Space.s1 + 2) {
                        Text(g.title).coreFont(size: MacTextSize.body, weight: .semibold)
                        if g.reading { LiveDot() }
                    }
                    Text(g.sub).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                CoreSwitch(isOn: Binding(get: { g.enabled }, set: { brain.setSource(g, on: $0) })).fixedSize()
                    .accessibilityLabel("Read \(g.title)")
                    .help(g.enabled ? "Stop reading \(g.title)" : "Start reading \(g.title)")
            }
            HStack(spacing: Space.s2) {
                stat(g.read.map { $0.formatted() } ?? "–", "read")
                if g.week != nil || brain.calm.v101 { stat(g.week.map { $0.formatted() } ?? "–", "this week") }
                stat(
                    g.enabled ? (g.last.map { SyncWords.ago($0) } ?? "Not yet") : "Off", g.enabled ? "last read" : "")
            }
            if g.reading { CoreBusyBar().accessibilityHidden(true) }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .coreWell()
        .accessibilityElement(children: .contain)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).coreFont(size: MacTextSize.title, weight: .semibold).monospacedDigit().lineLimit(1)
                .contentTransition(.numericText())
            Text(label.isEmpty ? " " : label).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassInk.well, in: coreShape(Radius.control))
    }

    /// Add a source: Import is the way in today.
    private var addCard: some View {
        Button {
            brain.openImport()
        } label: {
            VStack(spacing: Space.s1) {
                Image(systemName: "plus").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                Text("Add a Source").coreFont(size: MacTextSize.body, weight: .semibold)
                Text("A folder of notes, a repository, or another tool’s history").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
            }
            .padding(Space.s4).frame(maxWidth: .infinity, minHeight: Space.s8 * 3)
            .background(GlassInk.well, in: coreShape(Radius.cardMac))
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain)
        .help("Add a source through Import (⌘I)")
    }
}

/// A small green square that says "live now". It fades in and out while shown (a fade, so Reduce Motion keeps it).
struct LiveDot: View {
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var dim = false

    var body: some View {
        coreShape(2).fill(palette.success).frame(width: 6, height: 6)
            .opacity(dim ? 0.35 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: reduce ? 1.8 : 1.2).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityHidden(true)
    }
}
