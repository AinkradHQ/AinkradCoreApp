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
                Text("Machines that do the work for your Core: terminals and agents.").foregroundStyle(palette.text2)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Space.s8 * 9), spacing: Space.s3, alignment: .top)],
                    spacing: Space.s3
                ) {
                    ForEach(shown) { r in
                        RunnerCard(model: model, runner: r).transition(
                            reduce ? .opacity : .scale(scale: 0.97).combined(with: .opacity))
                    }
                }
                .animation(Motion.calm(.smooth(duration: 0.3), reduce), value: shown.map(\.id))
                if shown.isEmpty {
                    Text("No runners match this filter.").foregroundStyle(palette.text2)
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: Space.s2) {
            Text("Runners").coreFont(size: MacTextSize.large, weight: .bold).accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.s3)
            if !model.runners.isEmpty {
                CoreSegmented(
                    "Show",
                    segments: RunnerFacts.Filter.allCases.map { f in
                        CoreSegment(f, "\(f.rawValue) \(model.runners.filter(f.matches).count)")
                    }, selection: $model.runnerFilter
                )
                .fixedSize()
            }
            AppActionTile(title: "Add runner", symbol: "plus", key: "⌘N", hue: GlassInk.blue, prominent: true) {
                model.host.runnerHost?.addRunner()
            }
            .keyboardShortcut("n", modifiers: .command)
            .help("Pair a new machine as a runner")
        }
    }

    private var empty: some View {
        VStack(spacing: Space.s3) {
            IconTile("server.rack", hue: GlassInk.slate, size: 52)
            Text("No runners yet").coreFont(size: MacTextSize.large, weight: .bold)
            Text("A runner is a machine that runs terminals and agents for your Core. Add the first one.")
                .foregroundStyle(palette.text2).multilineTextAlignment(.center)
                .frame(maxWidth: Space.s8 * 8)
        }
        .frame(maxWidth: .infinity).padding(.top, Space.s8)
    }
}

/// What a runner offers, as a chip: on is blue, off is quiet. Symbol and word, so colour is never the only cue.
struct OfferChip: View {
    let symbol: String
    let title: String
    let on: Bool
    var body: some View {
        Label("\(title) \(on ? "on" : "off")", systemImage: symbol)
            .coreFont(size: MacTextSize.meta, weight: .medium)
            .foregroundStyle(on ? GlassInk.blue : GlassInk.secondary)
            .padding(.horizontal, Space.s2).frame(minHeight: MacSize.chip + 4)
            .background(on ? GlassInk.blue.opacity(0.18) : GlassInk.well, in: coreShape(Radius.chip))
    }
}

/// "This Core (built-in)": the runner that lives inside this Core.
struct BuiltInBadge: View {
    var body: some View {
        Text("This Core (built-in)").coreFont(size: MacTextSize.meta, weight: .medium).foregroundStyle(GlassInk.blue)
            .padding(.horizontal, Space.s2).frame(minHeight: MacSize.chip)
            .background(GlassInk.blue.opacity(0.18), in: coreShape(Radius.chip)).lineLimit(1).fixedSize()
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
                        "server.rack", hue: facts.status == .off ? GlassInk.slate : RunnerHue.of(runner.name), size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: Space.s2) {
                            Text(runner.name).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
                            if runner.builtIn { BuiltInBadge() }
                        }
                        Text(facts.system ?? "System not reported yet").coreFont(size: MacTextSize.meta)
                            .foregroundStyle(palette.text2)
                    }
                    Spacer(minLength: Space.s2)
                    RunnerChip(facts: facts)
                }
                if let say = facts.say {
                    Text(say).coreFont(size: MacTextSize.meta).fixedSize(horizontal: false, vertical: true)
                        .padding(Space.s2).frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            palette.tone(facts.status == .off ? .queue : .warn).fill, in: coreShape(Radius.control))
                }
                HStack(spacing: Space.s2) {
                    OfferChip(symbol: "terminal", title: "Terminals", on: facts.terminalsOn)
                    OfferChip(symbol: "sparkles", title: "Agents", on: facts.agentsOn)
                }
                RunnerBars(facts: facts, terminalsHere: terminals)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Load, while this Mac watched").coreFont(size: MacTextSize.meta).foregroundStyle(
                            palette.text2)
                        if let s = model.loadSamples[runner.id], s.count >= 2 {
                            CoreSpark(s, tone: facts.status == .busy ? .warn : .run, ceiling: max(0.5, s.max() ?? 0.5))
                                .frame(height: 30)
                        } else {
                            Text("Not reported yet").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                        }
                    }
                    Spacer(minLength: Space.s2)
                    Label("Open", systemImage: "chevron.right").coreFont(size: MacTextSize.meta, weight: .semibold)
                        .foregroundStyle(palette.text2).opacity(hovering ? 1 : 0)
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? palette.rowHover : palette.glassCard, in: coreShape(Radius.cardMac))
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .accessibilityLabel(
            "\(runner.name), \(facts.chip), \(runner.load) of \(runner.capacity) work slots in use")
    }
}
