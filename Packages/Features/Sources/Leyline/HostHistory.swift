import CoreUI
import Projects
import SwiftUI

/// History: everything that happened on this host, newest first, cut into days, filtered by who did it. A row opens in place
/// with its details, and a recorded terminal replays there (output only, redacted by the Core before it was stored).
struct HostTimelineSection: View {
    let state: HostPageState

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HostSectionTitle("History", line: "who did what, newest first")
            HStack(spacing: Space.s1) {
                ForEach(HostTimeline.filters, id: \.title) { f in
                    AppFilterTile(title: f.title, count: -1, on: state.who == f.who, key: "") { state.who = f.who }
                        .accessibilityIdentifier("history-filter-\(f.title)")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Show")
            content
        }
        .onDisappear { state.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("host-history")
    }

    @ViewBuilder private var content: some View {
        switch state.history {
        case .idle, .loading:
            VStack(spacing: Space.s1) {
                ForEach(0..<4, id: \.self) { _ in CoreSkeleton().frame(height: Space.s8 + Space.s3) }
            }
        case .missing:
            Text(HostWords.gone("History")).foregroundStyle(GlassInk.secondary)
        case .failed(let why):
            CoreNotice(symbol: "exclamationmark.triangle", title: "History did not load", text: why, tone: .warn) {
                Button("Try Again") { Task { await state.loadHistory() } }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
        case .ready:
            let days = HostTimeline.days(state.shownHistory)
            if days.isEmpty {
                Text(
                    state.who == nil
                        ? "Nothing has happened here yet. Terminals, commands, files and AI requests show up here."
                        : "Nothing from \(HostTimeline.filters.first { $0.who == state.who }?.title ?? "them") yet."
                )
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Space.s3) {
                    ForEach(days) { day in
                        VStack(alignment: .leading, spacing: Space.s1) {
                            Text(day.title).coreFont(size: MacTextSize.meta, weight: .semibold)
                                .foregroundStyle(GlassInk.secondary).padding(.leading, Space.s2)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(day.events) { TimelineRow(event: $0, state: state) }
                        }
                    }
                }
            }
        }
    }
}

/// One thing that happened: who (the glyph), what, a line of detail and when. A click opens it in place.
private struct TimelineRow: View {
    let event: HostEvent
    let state: HostPageState
    @State private var hover = false
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var open: Bool { state.opened == event.id }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                IconTile(
                    HostWords.symbol(event.who), hue: event.who == .system ? GlassInk.amber : palette.btnPrimary,
                    size: Space.s6 + Space.s1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.what).coreFont(size: MacTextSize.body, weight: .medium).lineLimit(1)
                    Text(line).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                if event.recording != nil {
                    Image(systemName: "play.rectangle").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary).accessibilityLabel("Has a recording")
                }
                Text(HostWords.ago(event.at)).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .monospacedDigit().lineLimit(1)
            }
            if open { detail.transition(.opacity) }
        }
        .padding(Space.s2)
        .modifier(SelectedFill(selected: open, hover: hover, radius: Radius.control + 2))
        .contentShape(coreShape(Radius.control + 2))
        .onTapGesture {
            withAnimation(Motion.calm(Motion.out(Motion.ui), reduce)) { state.opened = open ? nil : event.id }
        }
        .onHover { hover = $0 }
        .animation(Motion.out(Motion.hover), value: hover)
        .help(open ? "Close the details" : "Open the details")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(HostWords.who(event.who)), \(event.what), \(HostWords.ago(event.at))")
        .accessibilityAddTraits(.isButton)
    }

    /// "You · relayed · recorded · 12 min".
    private var line: String {
        ([HostWords.who(event.who)] + (event.detail.isEmpty ? [] : [event.detail])
            + (event.minutes.map { ["\($0) min"] } ?? [])).joined(separator: " · ")
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Grid(alignment: .leading, horizontalSpacing: Space.s3, verticalSpacing: Space.s1) {
                fact("When", event.at?.formatted(date: .abbreviated, time: .standard) ?? "Not recorded")
                fact("Who", HostWords.who(event.who))
                if !event.detail.isEmpty { fact("How", event.detail) }
                if let m = event.minutes { fact("Took", m == 1 ? "1 minute" : "\(m) minutes") }
            }
            if event.recording != nil {
                if state.replaying?.id == event.id {
                    ReplayPlayer(state: state)
                } else {
                    Button {
                        Task { await state.replay(event) }
                    } label: {
                        Label("Replay Recording", systemImage: "play.fill")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .help("Replay what the terminal showed (Touch ID)")
                }
            }
        }
        .padding(.leading, Space.s8 + Space.s1)
    }

    private func fact(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(GlassInk.secondary)
            Text(v).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .coreFont(size: MacTextSize.meta)
    }
}

/// A recording, replayed as text: play and pause, the position, the length and the speed.
private struct ReplayPlayer: View {
    let state: HostPageState
    @State private var speed = 1

    var body: some View {
        switch state.recording {
        case .idle: EmptyView()
        case .loading: CoreWorkingBar()
        case .missing: Text(HostWords.gone("Replay")).foregroundStyle(GlassInk.secondary)
        case .failed(let why): Text(why).foregroundStyle(GlassInk.secondary)
        case .ready(let r): player(r)
        }
    }

    private func player(_ r: Recording) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ScrollView {
                Text(r.text(at: state.position)).coreFont(size: MacTextSize.meta, design: .monospaced)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(Space.s2)
            }
            .frame(height: Space.s8 * 5)
            .background(GlassInk.well, in: coreShape(Radius.control))
            HStack(spacing: Space.s2) {
                CoreIconButton(
                    symbol: state.playing ? "pause" : "play",
                    label: state.playing ? "Pause the replay" : "Play the replay"
                ) {
                    if state.playing { state.stop() } else { state.play() }
                }
                Text(Self.clock(state.position)).monospacedDigit()
                CoreMeter(r.length > 0 ? state.position / r.length : 0, label: "Replay position")
                Text(Self.clock(r.length)).monospacedDigit()
                CoreSegmented(
                    "Speed", segments: [CoreSegment(1, "1×"), CoreSegment(2, "2×"), CoreSegment(4, "4×")],
                    selection: $speed
                )
                .fixedSize()
            }
            .coreFont(size: MacTextSize.meta)
        }
        .onChange(of: speed) { _, s in state.speed = Double(s) }
    }

    private static func clock(_ s: Double) -> String {
        let n = Int(s)
        return String(format: "%02d:%02d", n / 60, n % 60)
    }
}
