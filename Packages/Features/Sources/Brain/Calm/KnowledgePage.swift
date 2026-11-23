import CoreUI
import SwiftUI

/// Knowledge as a library, never one list of thousands: ask it, browse it by topic, see the newest decisions and what it
/// learned today. A topic opens its list by place with the side panel. An older Core has no ask and no topics: the page
/// lists the best-supported facts instead.
struct KnowledgePage: View {
    let brain: BrainModel
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    private var calm: BrainCalmModel { brain.calm }

    var body: some View {
        let s = calm.summary("knowledge")
        VStack(alignment: .leading, spacing: Space.s4) {
            if let t = calm.topic {
                BrainHead(
                    symbol: "sparkles", title: t.name, crumb: "Knowledge", count: t.count,
                    sub: "Everything Brain knows about \(t.name.lowercased()), by place",
                    back: { Task { await calm.openTopic(nil) } }
                ) { EmptyView() }
                TopicList(brain: brain, places: t.rooms, topic: t.name).transition(.opacity)
            } else {
                BrainHead(
                    symbol: "sparkles", title: "Knowledge", count: s?.count,
                    sub: "Facts and decisions about your projects", today: s?.today ?? 0)
                if calm.v101 || calm.topics != nil {
                    ScrollView { library.frame(maxWidth: .infinity, alignment: .leading) }.transition(.opacity)
                } else {
                    TopicList(brain: brain, places: [], topic: nil)
                }
            }
        }
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: calm.topic?.name)
        .onAppear { shown = true }
        .accessibilityIdentifier("brain-knowledge")
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            AskBox(calm: calm).coreRise(shown, 0)
            if let a = calm.answer { AnswerCard(answer: a).transition(.opacity) }
            if let topics = calm.topics, !topics.isEmpty {
                topicsCard(topics).coreRise(shown, 1)
            }
            HStack(alignment: .top, spacing: Space.s4) {
                decisionsCard.frame(maxWidth: .infinity)
                learnedCard.frame(maxWidth: .infinity)
            }
            .coreRise(shown, 2)
        }
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: calm.answer)
    }

    private func topicsCard(_ topics: [TopicWire]) -> some View {
        let top = Double(max(topics.first?.count ?? 1, 1))
        return VStack(alignment: .leading, spacing: Space.s3) {
            BrainCardHead(title: "Topics") { Text("What it knows most about · choose one to open it") }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s3), count: 4), spacing: Space.s3)
            {
                ForEach(Array(topics.enumerated()), id: \.element.id) { i, t in
                    TopicTile(topic: t, share: Double(t.count) / top, symbol: Self.symbol(t.name, i)) {
                        Task { await calm.openTopic(t) }
                    }
                }
            }
        }
        .padding(Space.s4).coreWell()
    }

    private var decisionsCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            BrainCardHead(title: "Recent decisions") {
                if calm.decisionsTotal > 0 { Text("\(calm.decisionsTotal.formatted()) in all").monospacedDigit() }
            }
            if calm.decisions.isEmpty {
                Text("No decisions yet.").coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
            }
            ForEach(calm.decisions) { d in
                HStack(alignment: .top, spacing: Space.s3) {
                    Text(SyncWords.date(d.createdAt).map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? "")
                        .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                        .frame(width: Space.s8 * 2, alignment: .leading)
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text(d.body).coreFont(size: MacTextSize.body).fixedSize(horizontal: false, vertical: true)
                        PlaceChip(name: d.roomName)
                    }
                }
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .topLeading).coreWell()
    }

    private var learnedCard: some View {
        let rows = calm.learned.filter { $0.area == "knowledge" }
        return VStack(alignment: .leading, spacing: Space.s3) {
            BrainCardHead(title: "Learned today") {
                if !rows.isEmpty { Text("+\(rows.count.formatted())").monospacedDigit() }
            }
            if rows.isEmpty {
                Text("Nothing new today.").coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
            }
            ForEach(rows.prefix(4)) { l in
                LearnedLine(symbol: "sparkles", line: l.line, meta: l.roomName) { brain.forget(l) }
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .topLeading).coreWell()
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: rows.map(\.id))
    }

    /// A topic's icon from its name, else a quiet default.
    static func symbol(_ name: String, _ i: Int) -> String {
        let n = name.lowercased()
        let table: [(String, String)] = [
            ("release", "square.and.arrow.down"), ("sign", "lock"), ("auth", "lock"), ("login", "lock"),
            ("build", "bolt"), ("data", "cylinder"), ("design", "star"), ("pay", "creditcard"), ("test", "checkmark"),
            ("deploy", "cloud"), ("api", "network"), ("doc", "doc.text"),
        ]
        return table.first { n.contains($0.0) }?.1 ?? "tag"
    }
}

/// "Ask what Brain knows": Return asks. The answer is written only when an AI account and a runner are there; the
/// sources always come back.
private struct AskBox: View {
    @Bindable var calm: BrainCalmModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "sparkles").brainAccentInk().accessibilityHidden(true)
            TextField("Ask what Brain knows, like “how do releases work?”", text: $calm.question)
                .textFieldStyle(.plain).coreFont(size: MacTextSize.title).focused($focused)
                .onSubmit { Task { await calm.ask() } }
                .onKeyPress(.escape) {
                    guard calm.answer != nil || !calm.question.isEmpty else { return .ignored }
                    calm.clearAnswer()
                    return .handled
                }
                .accessibilityLabel("Ask what Brain knows")
            if calm.asking { ProgressView().controlSize(.small) } else { CoreKeycap("⏎").accessibilityHidden(true) }
        }
        .padding(.horizontal, Space.s4)
        .frame(height: Space.s8 + Space.s4)
        .coreFieldSurface(focused: focused, radius: Radius.cardMac)
        .help("Ask a question and press Return")
        .accessibilityIdentifier("brain-ask")
    }
}

/// The written answer and the records it rests on.
private struct AnswerCard: View {
    let answer: AskWire
    @Environment(\.coreAccent) private var accent

    var body: some View {
        let places = Array(Set(answer.sources.map(\.roomName))).sorted()
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Image(systemName: "sparkles").brainAccentInk().accessibilityHidden(true)
                Text(answer.answer == nil ? "Best matches from what Brain knows" : "From what Brain knows")
                    .coreFont(size: MacTextSize.body, weight: .semibold)
                Spacer(minLength: Space.s2)
                Text(
                    ([BrainWords.plural(answer.sources.count, "source", "sources")] + places.prefix(2))
                        .joined(separator: " · ")
                )
                .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
            }
            if answer.sources.isEmpty {
                Text("Brain does not know anything about that yet.").coreFont(size: MacTextSize.body)
                    .foregroundStyle(GlassInk.secondary)
            } else if let text = answer.answer {
                // A written answer (a later Core), with the records it rests on as chips.
                Text(text).coreFont(size: MacTextSize.title).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                FlowChips(items: answer.sources.map(\.body))
            } else {
                // No written answer: the matches are the result.
                ForEach(answer.sources) { src in
                    LearnedLine(
                        symbol: src.type == "decision" ? "star" : "sparkles", line: src.body,
                        meta: "\(src.type == "decision" ? "Decision" : "Fact") · \(src.roomName)", forget: nil)
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassInk.accent(accent).opacity(0.12), in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-answer")
    }
}

/// The sources under an answer, as chips that wrap.
private struct FlowChips: View {
    let items: [String]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.s2) { chips }
            VStack(alignment: .leading, spacing: Space.s1) { chips }
        }
    }
    private var chips: some View {
        ForEach(Array(items.prefix(4).enumerated()), id: \.offset) { _, s in
            HStack(spacing: Space.s1) {
                Image(systemName: "sparkles").accessibilityHidden(true)
                Text(s).lineLimit(1).truncationMode(.tail)
            }
            .coreFont(size: MacTextSize.meta)
            .frame(maxWidth: Space.s8 * 9, alignment: .leading)
            .padding(.horizontal, Space.s2).padding(.vertical, 3)
            .background(GlassInk.well, in: coreShape(Radius.chip))
            .help(s)
        }
    }
}

/// A topic: its name, count, share of the biggest, and an example.
private struct TopicTile: View {
    let topic: TopicWire
    let share: Double
    let symbol: String
    let open: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    BrainTile(symbol: symbol, size: Space.s6)
                    Text(topic.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                    Spacer(minLength: Space.s1)
                    Text(topic.count.formatted()).coreFont(size: MacTextSize.body, weight: .semibold).monospacedDigit()
                }
                CoreMeter(share, label: "\(topic.name), \(topic.count) things")
                Text("“\(topic.example)”").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, minHeight: Space.s8 * 3, alignment: .topLeading)
            .background(hover ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.cardMac))
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Open \(topic.name)")
        .accessibilityIdentifier("brain-topic-\(topic.name)")
    }
}
