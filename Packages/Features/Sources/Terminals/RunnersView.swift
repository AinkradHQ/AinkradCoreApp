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

    private var shown: [RunnerItem] { RunnerFacts.ordered(model.runners.filter(model.runnerFilter.matches)) }

    @ViewBuilder private var fleet: some View {
        switch model.load {
        case .failed(let m): ConnectionBanner(.error(m), retry: { Task { await model.reload() } })
        default:
            toolbar
            if model.runners.isEmpty {
                if model.load == .ready { empty } else { CoreBusyBar() }
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Space.s8 * 16), spacing: Space.s3, alignment: .top)],
                    spacing: Space.s3
                ) {
                    ForEach(shown) { r in
                        RunnerCard(model: model, runner: r).transition(
                            reduce ? .opacity : .scale(scale: 0.97).combined(with: .opacity))
                    }
                }
                .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: shown.map(\.id))
                if shown.isEmpty {
                    Text("No runners match this filter.").foregroundStyle(palette.text2)
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: Space.s2) {
            Text("Runners").coreFont(size: MacTextSize.title, weight: .semibold).accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.s3)
            if !model.runners.isEmpty {
                ForEach(RunnerFacts.Filter.allCases) { f in
                    AppFilterTile(
                        title: f.rawValue, count: model.runners.filter(f.matches).count, on: model.runnerFilter == f,
                        key: ""
                    ) { model.runnerFilter = f }
                    .help("Show \(f == .all ? "all runners" : "runners that are \(f.rawValue.lowercased())")")
                }
            }
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
    @Environment(\.corePalette) private var palette
    var body: some View {
        Label("\(title) \(on ? "on" : "off")", systemImage: symbol)
            .coreFont(size: MacTextSize.meta, weight: .medium)
            .foregroundStyle(on ? palette.primary : palette.text2)
            .padding(.horizontal, Space.s2).frame(minHeight: MacSize.chip)
            .background(on ? palette.tone(.done).fill : palette.uDim, in: coreShape(Radius.chip))
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
    @Environment(\.corePalette) private var palette
    var body: some View {
        Text(text).coreFont(size: MacTextSize.meta, weight: .medium).foregroundStyle(palette.primary)
            .padding(.horizontal, Space.s2).frame(minHeight: MacSize.chip)
            .background(palette.tone(.done).fill, in: coreShape(Radius.chip)).lineLimit(1).fixedSize()
    }
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

private struct RunnerCard: View {
    let model: TerminalsModel
    let runner: RunnerItem
    @Environment(\.corePalette) private var palette
    @State private var hovering = false

    var body: some View {
        let facts = RunnerFacts(runner: runner)
        let terminals = model.onRunner(runner.id)
        Button {
            model.runnerDetail = runner.id
        } label: {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s3) {
                    IconTile(
                        model.host.thisMacRunnerID == runner.id ? "laptopcomputer" : "server.rack",
                        hue: facts.status == .off ? GlassInk.slate : GlassInk.blue, size: Space.s8 + Space.s2)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: Space.s2) {
                            Text(runner.name).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
                            if runner.builtIn { BuiltInBadge() }
                            if model.host.thisMacRunnerID == runner.id { ThisMacBadge() }
                        }
                        Text(facts.system ?? "System not reported yet").coreFont(size: MacTextSize.meta)
                            .foregroundStyle(palette.text2)
                    }
                    Spacer(minLength: Space.s2)
                    RunnerChip(facts: facts)
                }
                if let say = facts.say, facts.status != .off { RunnerSay(text: say, off: false) }
                HStack(spacing: Space.s2) {
                    OfferChip(symbol: "terminal", title: "Terminals", on: facts.terminalsOn)
                    OfferChip(symbol: "bubble.left", title: "AI sessions", on: facts.agentsOn)
                }
                RunnerBars(facts: facts, terminalsHere: terminals)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Load, last 10 minutes").coreFont(size: MacTextSize.meta).foregroundStyle(
                            palette.text2)
                        if let s = model.loadSamples[runner.id], s.count >= 2 {
                            CoreSpark(s, ceiling: max(0.5, s.max() ?? 0.5)).frame(height: Space.s8 + Space.s2)
                        } else {
                            Text("Not reported yet").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Label("Open", systemImage: "chevron.right").coreFont(size: MacTextSize.meta, weight: .semibold)
                        .foregroundStyle(palette.text2).opacity(hovering ? 1 : 0)
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .coreWell(active: hovering)
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(CardPress())
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .help("Open \(runner.name)")
        .accessibilityLabel(
            "\(runner.name), \(facts.chip), \(runner.load) of \(runner.capacity) work slots in use")
    }
}

/// A runner card's press: scale 0.98 with the press curve; Reduce Motion darkens the card instead. Hover stays with the
/// card's well. Local until CoreUI makes its tile press public.
private struct CardPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { PressBody(configuration: configuration) }

    private struct PressBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduce
        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduce ? 0.98 : 1)
                .overlay {
                    coreShape(Radius.cardMac).fill(.black.opacity(configuration.isPressed && reduce ? 0.18 : 0))
                        .allowsHitTesting(false)
                }
                .animation(Motion.press(Motion.press), value: configuration.isPressed)
        }
    }
}
