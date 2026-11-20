import CoreUI
import SwiftUI

/// The Runners pane: the machines that do the work for your Core, as cards, or one machine's page (N19). Only what runners
/// report: state, what they offer, work slots, load per core.
/// E2's Devices & Runners app shows this as its Runners tab: `RunnersView(model:)`, filling the tab body. It carries its own
/// heading and Add runner button, and opens a runner's page in place (`model.runnerDetail`), so the tab needs no navigation.
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
                RunnerSummary(model: model)
                VStack(spacing: Space.s2 + 2) {
                    ForEach(shown) { r in
                        RunnerRow(model: model, runner: r).transition(
                            reduce ? .opacity : .scale(scale: 0.97).combined(with: .opacity))
                    }
                }
                .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: shown.map(\.id))
                if shown.isEmpty {
                    Text("No runners are \(model.runnerFilter?.rawValue.lowercased() ?? "here").").foregroundStyle(
                        palette.text2)
                }
                Text(
                    "Tap a runner to see what it is doing. Ainkrad installs and updates Claude, Codex, OpenCode and Antigravity on every runner for you."
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            }
        }
    }

    /// "Runners", one sentence of what is going on, and Add runner.
    private var header: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Runners").coreFont(size: MacTextSize.large + 6, weight: .semibold).accessibilityAddTraits(
                    .isHeader)
                Text(summaryLine).coreFont(size: MacTextSize.body).foregroundStyle(palette.text2)
            }
            Spacer(minLength: Space.s3)
            Button {
                model.host.runnerHost?.addRunner()
            } label: {
                Label("Add runner", systemImage: "plus")
            }
            .buttonStyle(CoreButtonStyle(.prominent))
            .keyboardShortcut("n", modifiers: .command).environment(\.coreKeycap, "⌘N")
            .help("Add a runner (⌘N)")
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
            symbol: "server.rack", title: "No runners yet",
            line: "A runner is a machine that runs terminals and AI sessions for your Core. Add the first one.",
            primary: CoreAction("Add runner") { model.host.runnerHost?.addRunner() }
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

/// The Runners tab for E2's Devices & Runners app shell: the heading, summary tiles, runner cards and the runner's own page.
public struct RunnersTab: View {
    let model: TerminalsModel
    public init(model: TerminalsModel) { self.model = model }
    public var body: some View { RunnersView(model: model) }
}
