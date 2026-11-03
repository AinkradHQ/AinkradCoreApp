import CoreUI
import SwiftUI

/// The streamed transcript: a lazy column, one row per entry with the seq as its identity, so an appended entry adds a row and
/// leaves the rest alone. It follows the end while you are at the end; scrolling up loads earlier entries.
struct TranscriptView: View {
    @Bindable var model: AgentsModel
    let store: TranscriptStore?
    let session: AgentSessionInfo
    @State private var atEnd = true
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        Group {
            if let store { content(store) } else { Color.clear }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(_ store: TranscriptStore) -> some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.s3) {
                        header(store)
                        ForEach(store.entries) { e in
                            EntryRow(entry: e).equatable().id(e.seq)
                        }
                        if session.live && store.load == .ready && !model.waiting(session.id) { Thinking() }
                        Color.clear.frame(height: 1).id("end")
                            .onAppear { atEnd = true }
                            .onDisappear { atEnd = false }
                    }
                    .padding(.horizontal, Space.s4).padding(.bottom, Space.s3)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: store.lastSeq) { _, _ in
                    if atEnd { proxy.scrollTo("end", anchor: .bottom) }
                }
                if !atEnd {
                    Button {
                        proxy.scrollTo("end", anchor: .bottom)
                    } label: {
                        Label("Jump to latest", systemImage: "arrow.down")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small)).coreGlass(radius: Radius.control)
                    .padding(Space.s4).transition(.opacity)
                }
            }
        }
    }

    @ViewBuilder
    private func header(_ store: TranscriptStore) -> some View {
        switch store.load {
        case .idle, .loading:
            Text("Loading the transcript…").meta(palette).frame(maxWidth: .infinity)
        case .failed(let why):
            NoticeBanner(notice: InlineNotice(title: "Could not load the transcript", detail: why, tone: .fail))
        case .ready:
            if store.hasEarlier {
                Text("Earlier entries load as you scroll up")
                    .meta(palette).frame(maxWidth: .infinity)
                    .onAppear { model.loadEarlier(session.id) }
            } else if store.entries.isEmpty {
                Text("Nothing here yet. The first entries arrive when the agent starts.").meta(palette)
                    .frame(maxWidth: .infinity)
            } else {
                Text("Start of the session").meta(palette).frame(maxWidth: .infinity)
            }
        }
    }
}

extension Text {
    fileprivate func meta(_ p: Palette) -> some View { font(.system(size: MacTextSize.body)).foregroundStyle(p.text2) }
}

/// Three small squares, the agent working. They rest under Reduce Motion.
private struct Thinking: View {
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.3, paused: reduce)) { ctx in
            let t = Int(ctx.date.timeIntervalSinceReferenceDate / 0.3) % 3
            HStack(spacing: Space.s1) {
                ForEach(0..<3, id: \.self) { i in
                    coreShape(1.5).fill(palette.text2).frame(width: 6, height: 6)
                        .opacity(reduce || i == t ? 1 : 0.4)
                }
            }
        }
        .padding(.vertical, Space.s1)
        .accessibilityLabel("The agent is working")
    }
}

/// One entry. Equatable, so SwiftUI skips rows whose entry did not change.
struct EntryRow: View, Equatable {
    let entry: TranscriptEntry
    @Environment(\.corePalette) private var palette
    @State private var expanded = false

    nonisolated static func == (a: EntryRow, b: EntryRow) -> Bool { a.entry == b.entry }

    var body: some View {
        switch entry.kind {
        case .user(let text):
            Text(text).font(.system(size: MacTextSize.body)).foregroundStyle(palette.btnInk)
                .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                .background(palette.btnPrimary, in: coreShape(Radius.cardMac))
                .frame(maxWidth: .infinity, alignment: .trailing).textSelection(.enabled)
                .accessibilityLabel("You: \(text)")
        case .assistant(let text):
            Text(text).font(.system(size: MacTextSize.body)).lineSpacing(3).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .toolUse(_, let name, let summary):
            tool(name, summary, trailing: nil)
        case .toolResult(_, let name, let ok, let code, let output, let ms):
            result(name, ok, code, output, ms)
        case .approvalRequest(_, let tool, let input, _):
            system("lock.shield", "Asked to use \(tool)\(input.isEmpty ? "" : ": \(input)")")
        case .approvalDecided(_, let approved):
            system(approved ? "checkmark" : "xmark", approved ? "Approved" : "Denied", tone: approved ? .run : .queue)
        case .started(let h, let resumed):
            system("play", resumed ? "Resumed\(h.map { " · \($0)" } ?? "")" : "Started\(h.map { " · \($0)" } ?? "")")
        case .interrupted(let reason):
            system("arrow.clockwise", "Interrupted" + (reason.isEmpty ? "" : ": \(reason)"), tone: .warn)
        case .gap(let from, let to):
            system("ellipsis", "Entries \(from) to \(to) were not kept", tone: .warn)
        case .ended(let kind, let reason):
            system(
                "stop.circle", "Ended: \(kind)" + (reason.map { $0.isEmpty ? "" : " · \($0)" } ?? ""),
                tone: kind == "succeeded" ? .run : .warn)
        case .note(let type, let detail):
            system("info.circle", detail.isEmpty ? type : "\(type): \(detail)")
        case .hidden: EmptyView()
        }
    }

    private func tool(_ name: String, _ summary: String, trailing: String?) -> some View {
        HStack(spacing: Space.s3) {
            Text(name).font(.system(size: MacTextSize.body)).foregroundStyle(palette.text2).frame(
                width: 64, alignment: .leading)
            Text(summary).font(.system(size: 12, design: .monospaced)).lineLimit(2).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .background(palette.glassCard, in: coreShape(Radius.control))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tool \(name): \(summary)")
    }

    private func result(_ name: String?, _ ok: Bool, _ code: Int?, _ output: String, _ ms: Int?) -> some View {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        let long = lines.count > 6
        let facts = [
            ok ? "ok" : "failed", code.map { "exit \($0)" }, ms.map { String(format: "%.1f s", Double($0) / 1000) },
        ]
        .compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Image(systemName: ok ? "checkmark" : "xmark.octagon").foregroundStyle(
                    palette.tone(ok ? .run : .fail).ink
                )
                .accessibilityHidden(true)
                Text("\(name.map { "\($0) · " } ?? "")\(facts)").font(
                    .system(size: MacTextSize.meta, design: .monospaced)
                )
                .foregroundStyle(palette.text2)
            }
            if !output.isEmpty {
                Text(long && !expanded ? lines.prefix(6).joined(separator: "\n") + "\n…" : output)
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(palette.text2)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.s3).background(palette.glassCard, in: coreShape(Radius.control))
                if long {
                    Button(expanded ? "Show less" : "Show all \(lines.count) lines") { expanded.toggle() }
                        .buttonStyle(CoreButtonStyle(.plain, size: .small))
                }
            }
        }
        .padding(.leading, Space.s4)
    }

    private func system(_ symbol: String, _ text: String, tone: Tone? = nil) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: symbol).accessibilityHidden(true)
            Text(text).lineLimit(2)
        }
        .font(.system(size: MacTextSize.body))
        .foregroundStyle(tone.map { palette.tone($0).ink } ?? palette.text2)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
    }
}
