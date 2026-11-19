import CoreUI
import SwiftUI

/// The Runners pane: the machines that do the work for your Core, as cards, or one machine's page (N19). Only what runners
/// report: state, what they offer, work slots, load per core.
struct RunnersView: View {
    @Bindable var model: TerminalsModel
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                if let id = model.runnerDetail, let r = model.runner(id) {
                    RunnerPage(model: model, runner: r)
                } else {
                    fleet
                }
            }
            .padding(Space.s4)
        }
        .appLookTheme(AppLookPrefs.shared("runners"))
        .task {
            // Load and heartbeat move without events: look again while this pane is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await model.reload()
            }
        }
        .onChange(of: model.runners) { _, now in
            if let id = model.runnerDetail, !now.contains(where: { $0.id == id }) { model.runnerDetail = nil }
        }
    }

    private var shown: [RunnerItem] {
        RunnerFacts.ordered(model.runners.filter { model.runnerBucket == nil || RunnerBucket(of: $0) == model.runnerBucket })
    }

    @ViewBuilder private var fleet: some View {
        switch model.load {
        case .failed(let m): ConnectionBanner(.error(m), retry: { Task { await model.reload() } })
        default:
            header
            if model.runners.isEmpty {
                if model.load == .ready { empty } else { CoreBusyBar() }
            } else {
                RunnerSummary(model: model)
                VStack(spacing: Space.s2) {
                    ForEach(shown) { r in
                        RunnerRow(model: model, runner: r).transition(reduce ? .opacity : .opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: shown.map(\.id))
                if shown.isEmpty {
                    Text("No runners match this filter.").foregroundStyle(palette.text2)
                }
                Text(
                    "Click a runner to see what it is doing. Ainkrad installs and updates Claude, Codex, OpenCode and Antigravity on every runner for you."
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            }
        }
    }

    private var header: some View {
        HStack(spacing: Space.s2) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Runners").coreFont(size: MacTextSize.title, weight: .semibold).accessibilityAddTraits(.isHeader)
                Text("The computers that do your work.\(RunnerBucket.sentence(model.runners))")
                    .foregroundStyle(palette.text2)
            }
            Spacer(minLength: Space.s3)
            Button {
                model.host.runnerHost?.addRunner()
            } label: {
                Label("Add runner", systemImage: "plus")
            }
            .buttonStyle(CoreButtonStyle(.prominent, size: .small))
            .keyboardShortcut("n", modifiers: .command).environment(\.coreKeycap, "⌘N")
            .help("Pair a new machine as a runner (⌘N)")
        }
    }

    private var empty: some View {
        CoreStateCard(
            symbol: "server.rack", title: "No runners yet",
            line: "A runner is a machine that runs terminals and AI sessions for your Core. Add the first one.",
            primary: CoreAction("Add runner") { model.host.runnerHost?.addRunner() }
        )
        .frame(maxWidth: .infinity).padding(.top, Space.s8 * 4)
    }
}

/// What a runner offers, as a chip: on is blue, off is quiet. Symbol and word, so colour is never the only cue.
struct OfferChip: View {
    let symbol: String
    let title: String
    let on: Bool
    var body: some View {
        let label = "\(title) \(on ? "on" : "off")"
        if on { StateBadge(label, tone: .done, symbol: symbol) } else { CoreChip(label, symbol: symbol, minWidth: 0) }
    }
}

/// "This Core": the runner that lives inside this Core.
struct BuiltInBadge: View {
    var body: some View { RunnerTag(text: "This Core").help("The runner built into this Core") }
}

/// "This Mac": the runner inside this app (N16).
struct ThisMacBadge: View {
    var body: some View { RunnerTag(text: "This Mac").help("The runner inside this app") }
}

/// A blue word beside a runner's name.
private struct RunnerTag: View {
    let text: String
    var body: some View { CoreChip(text, minWidth: 0).lineLimit(1).fixedSize() }
}

/// What a runner's state means right now, as one line in a well: "Very busy: load 3.2 per core…".
struct RunnerSay: View {
    let text: String
    let off: Bool
    @Environment(\.corePalette) private var palette
    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: off ? "info.circle" : "exclamationmark.triangle")
                .foregroundStyle(palette.tone(off ? .queue : .warn).ink)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coreWell(radius: Radius.control)
    }
}

/// The agent and terminal bars, separate, from `slots`; the old single work-slot bar when the Core sent none.
struct RunnerBars: View {
    let facts: RunnerFacts
    let terminalsHere: Int
    var body: some View {
        let r = facts.runner
        HStack(alignment: .top, spacing: Space.s3) {
            if let a = facts.agentBar {
                RunnerBar(text: a.text, value: a.value, warn: a.full)
            } else if r.slots == nil {
                RunnerBar(
                    text: "\(r.load) of \(r.capacity) work slots",
                    value: r.capacity > 0 ? Double(r.load) / Double(r.capacity) : 0,
                    warn: r.capacity > 0 && r.load >= r.capacity)
            }
            if let t = facts.terminalBar(fallbackUsed: terminalsHere) {
                RunnerBar(text: t.text, value: t.value)
            }
        }
    }
}

/// A runner's state as a badge with the plain word.
struct RunnerChip: View {
    let facts: RunnerFacts
    var body: some View {
        let s = facts.status
        StateBadge(facts.chip, tone: s.tone, symbol: s.symbol)
    }
}

/// A labelled bar: the words say the numbers, the bar shows the share.
struct RunnerBar: View {
    let text: String
    let value: Double
    var warn = false
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(text).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).monospacedDigit()
                .contentTransition(.numericText())
            CoreMeter(value, low: warn, label: text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
