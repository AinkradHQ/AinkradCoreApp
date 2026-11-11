import Charts
import CoreUI
import SwiftUI

/// One runner's page (N18, N19): a header, then Now, What it offers, Machine, Who may use it and Actions. Plain words, no
/// internal codes; what the Core does not report says "Not reported yet".
struct RunnerPage: View {
    @Bindable var model: TerminalsModel
    let runner: RunnerItem
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var facts: RunnerFacts { RunnerFacts(runner: runner) }
    private var off: Bool { facts.status == .off }
    private var busy: Bool { facts.status == .busy }
    private var work: [RunnerWork] { model.host.runnerHost?.agentWork(on: runner.id) ?? [] }
    private var here: [TerminalItem] { model.items.filter { $0.runner == runner.id && !$0.isEnded } }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            header
            if let say = facts.say {
                Text(say).fixedSize(horizontal: false, vertical: true)
                    .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.tone(off ? .queue : .warn).fill, in: coreShape(Radius.cardMac))
            }
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(spacing: Space.s3) {
                    now
                    offers
                }
                VStack(spacing: Space.s3) {
                    machine
                    who
                    actions
                }
                .frame(width: Space.s8 * 11)
            }
        }
        .coreFont(size: MacTextSize.body)
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: Space.s3) {
            Button {
                model.runnerDetail = nil
            } label: {
                Label("Runners", systemImage: "chevron.backward")
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small)).keyboardShortcut(.escape, modifiers: [])
            IconTile("server.rack", hue: off ? GlassInk.slate : RunnerHue.of(runner.name), size: 32)
            Text(runner.name).coreFont(size: MacTextSize.large, weight: .bold).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            RunnerChip(facts: facts)
            Spacer(minLength: Space.s3)
            Button {
                Task { await model.runNoop(runner.id) }
            } label: {
                Label("Test it", systemImage: "waveform.path.ecg")
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(off || model.noop[runner.id] == .running)
            Button {
                model.openNew(runner: runner.id)
            } label: {
                Label("Open a terminal here", systemImage: "terminal")
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(!canTerminal)
        }
    }

    private var canTerminal: Bool { !off && !busy && facts.terminalsOn }

    // MARK: sections

    private func card<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(title).coreFont(size: MacTextSize.title, weight: .semibold).accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.glassCard, in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .contain)
    }

    private var now: some View {
        card("Now") {
            if off {
                Text("Nothing is running here. Work that was running continues when \(runner.name) is back.")
                    .foregroundStyle(palette.text2)
            } else {
                let terminals = here.count
                HStack(alignment: .top, spacing: Space.s4) {
                    RunnerBar(
                        text: "\(runner.load) of \(runner.capacity) work slots",
                        value: runner.capacity > 0 ? Double(runner.load) / Double(runner.capacity) : 0,
                        warn: runner.capacity > 0 && runner.load >= runner.capacity)
                    if let cap = facts.terminalCapacity {
                        RunnerBar(
                            text: "\(terminals) of \(cap) terminals",
                            value: cap > 0 ? Double(terminals) / Double(cap) : 0)
                    }
                }
                VStack(spacing: Space.s2) {
                    ForEach(work) { w in
                        workRow("sparkles", w.title, w.detail, bar: min(Double(w.minutes) / 60, 1)) {
                            model.host.runnerHost?.openAgent(w.id)
                        }
                        .transition(reduce ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }
                    ForEach(here.prefix(5)) { t in
                        workRow(
                            "terminal", "Terminal \(t.id)", t.attached == 0 ? "Not attached" : "\(t.attached) attached",
                            bar: nil
                        ) { model.openTerminal(t.id, attach: false) }
                        .transition(reduce ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }
                    if here.count > 5 {
                        Text("and \(here.count - 5) more terminals").foregroundStyle(palette.text2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if work.isEmpty && here.isEmpty {
                        Text("Nothing is running here.").foregroundStyle(palette.text2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .animation(Motion.calm(.smooth(duration: 0.35), reduce), value: work.map(\.id) + here.map(\.id))
                loadChart
            }
            if let n = model.noop[runner.id] { noopLine(n) }
        }
    }

    private func workRow(_ symbol: String, _ title: String, _ detail: String, bar: Double?, open: @escaping () -> Void)
        -> some View
    {
        HStack(spacing: Space.s3) {
            Image(systemName: symbol).foregroundStyle(GlassInk.blue).frame(width: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                Text(detail).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            if let bar { CoreMeter(bar, label: "Running time").frame(width: 70) }
            Button("Open", action: open).buttonStyle(CoreButtonStyle(.secondary, size: .small))
        }
        .padding(Space.s2).background(GlassInk.well, in: coreShape(Radius.control + 2))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var loadChart: some View {
        if let s = model.loadSamples[runner.id], s.count >= 2 {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Host load per core, while this Mac watched").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(palette.text2)
                Chart(Array(s.enumerated()), id: \.offset) { i, v in
                    AreaMark(x: .value("Time", i), y: .value("Load", v)).foregroundStyle(
                        LinearGradient(
                            colors: [palette.primary.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Time", i), y: .value("Load", v)).foregroundStyle(palette.primary)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
                .chartYScale(domain: 0...max(0.5, s.max() ?? 0.5)).chartXAxis(.hidden).chartYAxis(.hidden)
                .animation(Motion.calm(.smooth(duration: 0.4), reduce), value: s)
                .frame(height: 70).accessibilityHidden(true)
            }
        }
    }

    private func noopLine(_ n: NoopOutcome) -> some View {
        Group {
            switch n {
            case .running: Text("Waiting for the runner…")
            case .answered(let ms): Text("\(runner.name) answered in \(ms) ms. No work was started.")
            case .failed(let m): Text(m)
            }
        }
        .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
    }

    private var offers: some View {
        card("What it offers") {
            offer(
                "terminal", "Terminals",
                facts.terminalsOn
                    ? "Open a shell on this runner."
                    : "Terminals are off here. Turn them on on the machine that runs this runner.",
                on: facts.terminalsOn)
            offer(
                "sparkles", "Agents",
                facts.agentsOn
                    ? (facts.tools.isEmpty
                        ? "Let agents work here."
                        : "Let agents work here. Tools found: \(facts.tools.joined(separator: ", ")).")
                    : "Agents are off here. Turn them on on the machine that runs this runner.", on: facts.agentsOn)
            offer(
                "chevron.left.forwardslash.chevron.right", "Run commands", "One-off commands without a session.",
                on: facts.commandsOn)
            HStack(spacing: Space.s3) {
                Image(systemName: "key").frame(width: 20).foregroundStyle(palette.text2).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Can use your accounts").coreFont(size: MacTextSize.body, weight: .medium)
                    Text("The Core does not say yet whether agents here can use your accounts.")
                        .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                }
                Spacer(minLength: Space.s2)
                StateBadge("Not reported yet", tone: .queue, symbol: "questionmark")
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func offer(_ symbol: String, _ title: String, _ help: String, on: Bool) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: symbol).frame(width: 20).foregroundStyle(on ? GlassInk.blue : palette.text2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).coreFont(size: MacTextSize.body, weight: .medium)
                Text(help).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s2)
            StateBadge(on ? "On" : "Off", tone: on ? .run : .queue, symbol: on ? "checkmark" : "minus")
        }
        .accessibilityElement(children: .combine)
    }

    private var machine: some View {
        card("Machine") {
            Grid(alignment: .leading, horizontalSpacing: Space.s3, verticalSpacing: Space.s2) {
                row("System", facts.system)
                row("Runner version", runner.version)
                row("Runs as", nil)
                row("Isolation", runner.isolationTiers.flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") })
                row("Connected since", nil)
                GridRow {
                    Text("Last heartbeat").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    if let d = runner.lastSeen {
                        Text(d, style: .relative).monospacedDigit()
                    } else {
                        Text("Never").foregroundStyle(palette.text2)
                    }
                }
                if let a = runner.avg1, let c = runner.cores {
                    row("Host load", "\(coreDecimal(a, 1)) on \(c) cores")
                }
            }
        }
    }

    private func row(_ k: String, _ v: String?) -> some View {
        GridRow {
            Text(k).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            if let v { Text(v).lineLimit(2) } else { Text("Not reported yet").foregroundStyle(palette.text2) }
        }
    }

    private var who: some View {
        card("Who may use it") {
            let people = (model.host.runnerHost?.people() ?? []).compactMap { p -> (RunnerPerson, String)? in
                RunnerFacts.access(p.scopes).map { (p, $0) }
            }
            ForEach(people, id: \.0.id) { p, words in
                HStack(spacing: Space.s3) {
                    Image(systemName: p.platform?.lowercased().contains("ios") == true ? "iphone" : "laptopcomputer")
                        .foregroundStyle(GlassInk.blue).frame(width: 20).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(p.name).coreFont(size: MacTextSize.body, weight: .medium).lineLimit(1)
                        Text(words).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if people.isEmpty {
                Text("No device is listed for this Core yet.").foregroundStyle(palette.text2)
            }
            Text("Connection: runner. It can only receive work from this Core.").coreFont(size: MacTextSize.meta)
                .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        card("Actions") {
            VStack(spacing: Space.s2) {
                action("Test it", "waveform.path.ecg", disabled: off || model.noop[runner.id] == .running) {
                    Task { await model.runNoop(runner.id) }
                }
                action("Open a terminal here", "terminal", disabled: !canTerminal) { model.openNew(runner: runner.id) }
                action("Start an agent here", "sparkles", disabled: off || !facts.agentsOn) {
                    model.host.runnerHost?.startAgent(on: runner.id)
                }
                action("Rename", "pencil", disabled: false) { model.confirmRename(runner) }
                action("Revoke runner", "trash", disabled: false, danger: true) { model.confirmRevoke(runner) }
            }
            if let why = unavailable {
                Text(why).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            }
        }
    }

    private var unavailable: String? {
        if off { return "Test, terminals and agents are not available while \(runner.name) is offline." }
        if busy { return "New terminals are refused while the host is over its load limit." }
        return nil
    }

    private func action(
        _ title: String, _ symbol: String, disabled: Bool, danger: Bool = false, run: @escaping () -> Void
    )
        -> some View
    {
        Button(action: run) {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(CoreButtonStyle(.secondary)).foregroundStyle(danger ? GlassInk.redInk : GlassInk.primary)
        .disabled(disabled)
    }
}
