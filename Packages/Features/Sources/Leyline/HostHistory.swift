import CoreUI
import Projects
import SwiftUI

/// History & recordings: who did what on this host, newest first, and the replay of a recorded terminal. A recording holds
/// output only, redacted by the Core before it was stored; the replay is plain text, not a terminal.
struct HostHistoryPage: View {
    let state: HostPageState
    @State private var settled = false

    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            HistoryIsland(state: state).coreRise(settled, 0)
            ReplayIsland(state: state).coreRise(settled, 1)
        }
        .onAppear { settled = true }
        .task { await state.loadHistory() }
        .onDisappear { state.stop() }
        .accessibilityIdentifier("host-page-History")
    }
}

private struct HistoryIsland: View {
    let state: HostPageState
    @State private var filter = "all"

    var body: some View {
        Island(
            title: "History", sub: "who did what, when",
            accessory: {
                CoreSegmented(
                    "Who",
                    segments: [
                        CoreSegment("all", "All"), CoreSegment("you", "You"), CoreSegment("ai", "AI"),
                        CoreSegment("fleet", "Fleet"),
                    ], selection: $filter
                )
                .fixedSize()
            }
        ) {
            switch state.history {
            case .idle, .loading: CoreSkeleton().frame(height: Space.s8 * 3)
            case .missing: Text(HostWords.gone("History")).foregroundStyle(GlassInk.secondary)
            case .failed(let why):
                CoreNotice(symbol: "exclamationmark.triangle", title: "History did not load", text: why, tone: .warn) {
                    Button("Retry") { Task { await state.loadHistory() } }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            case .ready:
                let shown = state.shownHistory
                if shown.isEmpty {
                    Text(HostSection.history.empty.line).foregroundStyle(GlassInk.secondary)
                } else {
                    ScrollView {
                        LazyVStack(spacing: Space.s1) {
                            ForEach(shown) { e in
                                CoreRow(
                                    "\(HostWords.who(e.who)) · \(e.what)" + (e.minutes.map { " · \($0) min" } ?? ""),
                                    subtitle: "\(HostWords.ago(e.at)) · \(e.detail)", symbol: HostWords.symbol(e.who),
                                    selected: state.replaying?.id == e.id,
                                    action: e.recording == nil ? nil : { Task { await state.replay(e) } }
                                ) {
                                    if e.recording != nil {
                                        Image(systemName: "play.circle").foregroundStyle(GlassInk.secondary)
                                            .accessibilityLabel("Has a recording")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: filter) { _, f in state.who = HostEvent.Who(rawValue: f) }
        .accessibilityIdentifier("history-list")
    }
}

private struct ReplayIsland: View {
    let state: HostPageState
    @State private var speed = 1

    var body: some View {
        Island("Recording", sub: state.replaying.map { "\(HostWords.who($0.who)) · \($0.what) · output only" }) {
            switch state.recording {
            case .idle:
                Text(
                    "Pick an entry with a recording to replay it. Recording is off unless you turn it on for the host."
                )
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            case .loading: CoreWorkingBar()
            case .missing: Text(HostWords.gone("Replay")).foregroundStyle(GlassInk.secondary)
            case .failed(let why): Text(why).foregroundStyle(GlassInk.secondary)
            case .ready(let r): player(r)
            }
        }
        .onChange(of: speed) { _, s in state.speed = Double(s) }
        .accessibilityIdentifier("history-replay")
    }

    private func player(_ r: Recording) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ScrollView {
                Text(r.text(at: state.position)).coreFont(size: MacTextSize.meta, design: .monospaced)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Space.s3).frame(maxHeight: .infinity).coreWell()
            HStack(spacing: Space.s3) {
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
        }
    }

    private static func clock(_ s: Double) -> String {
        let n = Int(s)
        return String(format: "%02d:%02d", n / 60, n % 60)
    }
}
