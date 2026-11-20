import CoreUI
import SwiftUI

/// The Hardware pane: the machines that do the work for your Core, one row each, or one machine's page (N19). What runners
/// report (state, what they offer, work slots) and, once the Core has hardware (E15), cores, memory, load, gate and pause.
/// E2's Devices & Runners app shows this as its Hardware tab: `HardwareView(model:)`, filling the tab body. It carries its own
/// heading and Add hardware button, and opens a machine's page in place (`model.runnerDetail`), so the tab needs no navigation.
struct HardwareView: View {
    @Bindable var model: TerminalsModel
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                if let id = model.runnerDetail, let r = model.runner(id) {
                    HardwarePage(model: model, runner: r)
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
                model.readLocalInstall()
                try? await Task.sleep(for: .seconds(model.runners.contains(where: model.isInstalling) ? 2 : 10))
                await model.reload()
            }
        }
        .onChange(of: model.runners) { _, now in
            if let id = model.runnerDetail, !now.contains(where: { $0.id == id }) { model.runnerDetail = nil }
        }
    }

    private var shown: [RunnerItem] {
        RunnerFacts.ordered(model.runners).filter { model.runnerFilter == nil || model.live($0) == model.runnerFilter }
    }

    @ViewBuilder private var fleet: some View {
        switch model.load {
        case .failed(let m): ConnectionBanner(.error(m), retry: { Task { await model.reload() } })
        default:
            if model.runners.isEmpty {
                header
                if model.load == .ready { empty } else { CoreBusyBar() }
            } else {
                header
                if model.pool?.decisionsOff == true {
                    RunnerSay(text: "Smart job routing is off: add a Google account.", off: true)
                        .help("Until then, a command no rule knows runs where you typed it.")
                }
                RunnerSummary(model: model)
                VStack(spacing: Space.s2 + 2) {
                    ForEach(shown) { r in
                        RunnerRow(model: model, runner: r).transition(
                            reduce ? .opacity : .scale(scale: 0.97).combined(with: .opacity))
                    }
                }
                .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: shown.map(\.id))
                if shown.isEmpty {
                    Text("No hardware is \(model.runnerFilter?.rawValue.lowercased() ?? "here").").foregroundStyle(
                        palette.text2)
                }
                Text(
                    "Tap a machine to see what it is doing. Ainkrad installs and updates Claude, Codex, OpenCode and Antigravity on every runner for you."
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            }
        }
    }

    /// "Hardware", one sentence of what is going on, and Add hardware.
    private var header: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hardware").coreFont(size: MacTextSize.large + 6, weight: .semibold).accessibilityAddTraits(
                    .isHeader)
                Text(summaryLine).coreFont(size: MacTextSize.body).foregroundStyle(palette.text2)
            }
            Spacer(minLength: Space.s3)
            Button {
                model.host.runnerHost?.addRunner()
            } label: {
                Label("Add hardware", systemImage: "plus")
            }
            .buttonStyle(CoreButtonStyle(.prominent))
            .keyboardShortcut("n", modifiers: .command).environment(\.coreKeycap, "⌘N")
            .help("Add hardware (⌘N)")
        }
    }

    /// "The computers that do your work. 2 are busy, 1 is getting ready."
    private var summaryLine: String {
        let live = model.runners.map(model.live)
        let busy = live.filter { $0 == .working }.count
        let ready = live.filter { $0 == .gettingReady }.count
        var parts: [String] = []
        if busy > 0 { parts.append("\(busy) \(busy == 1 ? "is" : "are") busy") }
        if ready > 0 { parts.append("\(ready) \(ready == 1 ? "is" : "are") getting ready") }
        return "The computers that do your work." + (parts.isEmpty ? "" : " " + parts.joined(separator: ", ") + ".")
    }

    private var empty: some View {
        CoreStateCard(
            symbol: "server.rack", title: "No hardware yet",
            line: "Hardware is a machine that does work for your Core: AI sessions and heavy jobs. Add the first one.",
            primary: CoreAction("Add hardware") { model.host.runnerHost?.addRunner() }
        )
        .frame(maxWidth: .infinity).padding(.top, Space.s8 * 4)
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
    /// False for remote hardware once the Core has hardware (E15): it opens no terminals, so it has no terminal bar.
    var showTerminals = true
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
            if showTerminals, let t = facts.terminalBar(fallbackUsed: terminalsHere) {
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

/// The Runners tab for E2's Devices & Runners app shell: the heading, summary tiles, runner cards and the runner's own page.
public struct HardwareTab: View {
    let model: TerminalsModel
    public init(model: TerminalsModel) { self.model = model }
    public var body: some View { HardwareView(model: model) }
}
