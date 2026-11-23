import CoreUI
import SwiftUI

/// About you, Rules, Knowledge and Timeline: each area its own page.
struct CalmArea: View {
    let brain: BrainModel

    var body: some View {
        Group {
            switch brain.calm.page {
            case .rules: RulesPage(brain: brain)
            case .knowledge: KnowledgePage(brain: brain)
            case .timeline: TimelinePage(brain: brain)
            default: AboutYouPage(brain: brain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("brain-area-page")
    }

    static func symbol(_ type: String) -> String {
        switch type {
        case "rule": "checkmark.circle"
        case "preference": "heart"
        case "decision": "checkmark.seal"
        case "fact": "lightbulb"
        case "task": "circle.dashed"
        case "project-state": "clock"
        default: "text.alignleft"
        }
    }
}

/// About you: empty, how it fills in (three steps) with Import History…; filled, who you are by
/// what Brain saw most, and what it learned grouped by kind, each with how sure it is.
struct AboutYouPage: View {
    let brain: BrainModel
    @State private var shown = false
    @Environment(\.coreAccent) private var accent
    private var calm: BrainCalmModel { brain.calm }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            BrainHead(
                symbol: "person", title: "About you", count: max(calm.summary("me")?.count ?? 0, calm.records.count),
                sub: "How you like to work")
            ScrollView {
                Group {
                    if calm.records.isEmpty && !calm.loading { empty } else { filled }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { shown = true }
    }

    private var empty: some View {
        VStack(spacing: Space.s4) {
            BrainTile(symbol: "person", lit: true, size: Space.s8 + Space.s6)
            Text("Brain does not know you yet").coreFont(size: MacTextSize.title, weight: .semibold)
            Text(
                "It learns how you like to work from your AI sessions: how you ask, what you correct, what you always repeat. Nothing here comes from your projects; this stays about you."
            )
            .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
            .frame(maxWidth: Space.s8 * 15)
            HStack(alignment: .top, spacing: Space.s3) {
                step(1, "You work as usual", "Ask AI sessions for things the way you always do.")
                step(2, "It notices patterns", "“Prefers short answers”, “Reviews before merging”.")
                step(3, "You stay in charge", "Every line here can be changed or forgotten.")
            }
            .frame(maxWidth: Space.s8 * 23)
            HStack(spacing: Space.s2) {
                Button {
                    brain.openImport()
                } label: {
                    Label("Import History…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(CoreButtonStyle(.prominent))
                .environment(\.coreKeycap, "⌘I")
                .help("Learn from your past AI sessions (⌘I)")
            }
        }
        .padding(Space.s8)
        .frame(maxWidth: .infinity)
        .coreWell()
        .coreRise(shown, 0)
        .accessibilityIdentifier("brain-me-empty")
    }

    private func step(_ n: Int, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("\(n)").coreFont(size: MacTextSize.meta, weight: .semibold).brainAccentInk()
                .frame(width: Space.s5, height: Space.s5)
                .background(GlassInk.accent(accent).opacity(0.2), in: coreShape(Radius.chip))
                .accessibilityHidden(true)
            Text(title).coreFont(size: MacTextSize.body, weight: .semibold).padding(.top, Space.s1)
            Text(text).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: Space.s8 * 3, alignment: .topLeading)
        .background(GlassInk.well, in: coreShape(Radius.control))
    }

    /// Filled: who you are (the tags Brain saw most), then the records grouped by kind.
    private var filled: some View {
        let tags = Dictionary(calm.records.flatMap(\.tags).map { ($0, 1) }, uniquingKeysWith: +)
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(5).map(\.key)
        let groups: [(String, [BrainAreaRecordWire])] = [
            ("How you like to work", calm.records.filter { $0.type == "preference" || $0.type == "rule" }),
            ("About you", calm.records.filter { $0.type != "preference" && $0.type != "rule" }),
        ].filter { !$0.1.isEmpty }
        return HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s3) {
                BrainTile(symbol: "person", lit: true, size: Space.s8 * 2)
                Text("You").coreFont(size: MacTextSize.large, weight: .semibold)
                Text(
                    "What Brain learned about how you work, from \(BrainWords.plural(calm.records.count, "thing", "things")) it saw."
                )
                .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if !tags.isEmpty {
                    HStack(spacing: Space.s1) {
                        ForEach(tags, id: \.self) { t in
                            Text(t).coreFont(size: MacTextSize.body).padding(.horizontal, Space.s2).padding(
                                .vertical, 3
                            )
                            .background(GlassInk.well, in: coreShape(Radius.chip))
                        }
                    }
                }
            }
            .padding(Space.s5)
            .frame(width: Space.s8 * 9.5, alignment: .leading)
            .coreWell()
            VStack(alignment: .leading, spacing: Space.s4) {
                ForEach(Array(groups.enumerated()), id: \.offset) { i, g in
                    VStack(alignment: .leading, spacing: Space.s3) {
                        BrainCardHead(title: g.0) { Text(g.1.count.formatted()).monospacedDigit() }
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: Space.s2), GridItem(.flexible())],
                            spacing: Space.s2
                        ) {
                            ForEach(g.1) { trait($0) }
                        }
                    }
                    .padding(Space.s4).coreWell()
                    .coreRise(shown, i + 1)
                }
            }
        }
        .accessibilityIdentifier("brain-me-filled")
    }

    private func trait(_ r: BrainAreaRecordWire) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(r.body).coreFont(size: MacTextSize.body).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            HStack {
                SureBars(support: r.support)
                Spacer(minLength: 0)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: Space.s8 * 2, alignment: .topLeading)
        .background(GlassInk.well, in: coreShape(Radius.control))
        .contextMenu {
            Button("Forget") { brain.forget(r) }
        }
        .help("Seen in \(BrainWords.plural(r.support, "session", "sessions")). Right-click to forget it.")
    }
}
