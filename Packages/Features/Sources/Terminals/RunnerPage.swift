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
            if let say = facts.say { RunnerSay(text: say, off: off) }
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(spacing: Space.s3) {
                    now
                    offers
                    tools
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
        HStack(alignment: .center, spacing: Space.s3) {
            BackButton("Runners") { model.runnerDetail = nil }.keyboardShortcut(.escape, modifiers: [])
            IconTile(
                model.host.thisMacRunnerID == runner.id ? "laptopcomputer" : "server.rack",
                hue: off ? GlassInk.slate : GlassInk.blue, size: Space.s8 - Space.s1)
            Text(runner.name).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            if runner.builtIn { BuiltInBadge() }
            if model.host.thisMacRunnerID == runner.id { ThisMacBadge() }
            RunnerChip(facts: facts)
            Spacer(minLength: Space.s3)
            Button {
                Task { await model.runNoop(runner.id) }
            } label: {
                Label("Test it", systemImage: "testtube.2")
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(off || model.noop[runner.id] == .running)
            .help(off ? unavailable ?? "" : "Ask \(runner.name) to answer without starting work")
            Button {
                model.openNew(runner: runner.id)
            } label: {
                Label("Open a terminal here", systemImage: "terminal")
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(!canTerminal)
            .help(unavailable ?? "Open a shell on \(runner.name)")
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
        .coreWell()
        .accessibilityElement(children: .contain)
    }

    private var now: some View {
        card("Now") {
            if off {
                Text("Nothing is running here.").foregroundStyle(palette.text2)
            } else {
                let terminals = here.count
                RunnerBars(facts: facts, terminalsHere: terminals)
                VStack(spacing: Space.s2) {
                    ForEach(work) { w in
                        workRow("bubble.left", w.title, w.detail) {
                            model.host.runnerHost?.openAgent(w.id)
                        }
                        .transition(reduce ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }
                    ForEach(here.prefix(5)) { t in
                        workRow(
                            "terminal", "Terminal \(t.id)", t.attached == 0 ? "Not attached" : "\(t.attached) attached"
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
                .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: work.map(\.id) + here.map(\.id))
                loadChart
            }
            if let n = model.noop[runner.id] { noopLine(n) }
        }
    }

    private func workRow(_ symbol: String, _ title: String, _ detail: String, open: @escaping () -> Void) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: symbol).foregroundStyle(palette.text2).frame(width: Space.s5).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                Text(detail).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            Button("Open", action: open).buttonStyle(CoreButtonStyle(.secondary, size: .small)).help("Open \(title)")
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .background(palette.uDim, in: coreShape(Radius.control))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var loadChart: some View {
        if let s = model.loadSamples[runner.id], s.count >= 2 {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Load per core, last 10 minutes").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                CoreSpark(s, ceiling: max(0.5, s.max() ?? 0.5)).frame(height: Space.s8 + Space.s6)
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
            controls(runner.policy)
            HStack(spacing: Space.s3) {
                Image(systemName: "key").frame(width: Space.s5).foregroundStyle(palette.text2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Can use your accounts").coreFont(size: MacTextSize.body, weight: .medium)
                    Text(accountsHelp).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s2)
                if let yes = facts.canUseAccounts {
                    StateBadge(yes ? "Yes" : "No", tone: yes ? .run : .queue, symbol: yes ? "checkmark" : "xmark")
                } else {
                    StateBadge("Not reported yet", tone: .queue, symbol: "questionmark")
                }
            }
            .padding(.horizontal, Space.s3)
            .accessibilityElement(children: .combine)
        }
    }

    /// The AI sessions row's line: the AI tools found here, else what it needs.
    private var aiLine: String { RunnerTools.aiLine(runner.tools) ?? "Needs an AI tool below" }

    // MARK: switches, capacity and tools (N17 step 5, N19)

    private var busyPolicy: Bool { model.policyBusy.contains(runner.id) }

    /// Terminals and AI sessions as switches, then the AI-sessions-at-once stepper once the runner reports its policy.
    /// Before it does, the switches show what it offers and the first flip sends a policy (`setPolicy` fills the rest).
    private func controls(_ known: RunnerPolicy?) -> some View {
        let p = known ?? RunnerPolicy(terminals: facts.terminalsOn, agents: facts.agentsOn, capacity: 2)
        return VStack(alignment: .leading, spacing: Space.s3) {
            offer("terminal", "Terminals", "Open a shell on this runner") {
                CoreSwitch(
                    "",
                    isOn: Binding(
                        get: { p.terminals }, set: { v in Task { await model.setPolicy(runner, terminals: v) } })
                )
                .accessibilityLabel("Terminals")
                .disabled(busyPolicy || off)
            }
            offer("bubble.left", "AI sessions", aiLine) {
                CoreSwitch(
                    "",
                    isOn: Binding(get: { p.agents }, set: { v in Task { await model.setPolicy(runner, agents: v) } })
                )
                .accessibilityLabel("AI sessions")
                .disabled(busyPolicy || off)
            }
            if known != nil, p.agents {
                offer("list.bullet", "AI sessions at the same time", "The runner restarts when this changes") {
                    CoreNumberStepper(value: p.capacity, in: 1...8, noun: "AI sessions at the same time") { n in
                        Task { await model.setPolicy(runner, capacity: n) }
                    }
                    .disabled(busyPolicy || off)
                }
                .accessibilityIdentifier("runner-capacity")
                .transition(.opacity)
            }
            if let n = model.policyNote[runner.id] {
                Label(n.text, systemImage: n.refused ? "exclamationmark.triangle" : "arrow.triangle.2.circlepath")
                    .coreFont(size: MacTextSize.meta)
                    .foregroundStyle(n.refused ? palette.tone(.warn).ink : palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("runner-policy-note")
            }
        }
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: p)
    }

    /// Tools found on the host, each with an Install button when missing and live progress while installing.
    private var tools: some View {
        card("Tools") {
            ForEach(RunnerTools.all, id: \.id) { t in toolRow(t) }
        }
    }

    /// One tool: its name, its version (or "Not installed", or the install's progress) and what can be done.
    private func toolRow(_ t: (id: String, name: String, help: String)) -> some View {
        let version = runner.tools[t.id]
        let inst = model.installs[runner.id]?[t.id]
        let installing = inst?.state == .running
        let failed = inst?.state == .failed
        return HStack(spacing: Space.s3) {
            Text(t.name).coreFont(size: MacTextSize.body, weight: .medium).frame(
                width: Space.s8 * 4, alignment: .leading)
            Group {
                if let inst, installing {
                    Text("Installing · \(inst.percent)%").monospacedDigit().contentTransition(.numericText())
                } else if failed {
                    Text(inst?.reason ?? "The install did not finish.").foregroundStyle(palette.tone(.warn).ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(version.map { $0.isEmpty ? "Installed" : $0 } ?? "Not installed")
                }
            }
            .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            Spacer(minLength: Space.s2)
            if let inst, installing {
                CoreMeter(Double(inst.percent) / 100, label: "Installing \(t.name)").frame(width: Space.s8 * 4)
            } else if version == nil || failed {
                Button(failed ? "Try again" : "Install") {
                    Task { await model.installTool(runner, t.id) }
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(off)
                .help(off ? unavailable ?? "" : "Install \(t.name) on \(runner.name). \(t.help)")
            } else {
                StateBadge("Installed", tone: .done, symbol: "checkmark")
            }
        }
        .frame(minHeight: MacSize.controlLg)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("runner-tool-\(t.id)")
    }

    private var accountsHelp: String {
        switch facts.accountsAnswer {
        case nil: "Not reported yet"
        case "Yes": "The key never leaves the Core"
        case let no?: no
        }
    }

    /// One "What it offers" row: icon, name and help on the left, its control on the right.
    private func offer<T: View>(
        _ symbol: String, _ title: String, _ help: String, @ViewBuilder trailing: () -> T
    ) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: symbol).frame(width: Space.s5).foregroundStyle(palette.text2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).coreFont(size: MacTextSize.body, weight: .medium)
                Text(help).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s2)
            trailing()
        }
        .padding(.horizontal, Space.s3)
        .accessibilityElement(children: .contain)
    }

    private var machine: some View {
        card("Machine") {
            Grid(alignment: .leading, horizontalSpacing: Space.s3, verticalSpacing: Space.s2) {
                row("System", facts.system)
                GridRow {
                    Text("Runner version").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    if let v = runner.version {
                        HStack(spacing: Space.s2) {
                            Text(v)
                            if facts.updateAvailable { StateBadge("Update available", tone: .done, symbol: "arrow.up") }
                        }
                    } else {
                        Text("Not reported yet").foregroundStyle(palette.text2)
                    }
                }
                row("Runs as", facts.runsAs)
                if let shell = facts.terminalShell { shellRow(shell) }
                row("Isolation", runner.isolationTiers.flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") })
                row("Connected since", runner.connectedSince.map { $0.formatted(date: .abbreviated, time: .shortened) })
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

    /// "Terminal shell": plain for the Ainkrad shell; for the login shell the reason, quiet, and what to do about it.
    private func shellRow(_ shell: RunnerFacts.TerminalShell) -> some View {
        GridRow {
            Text("Terminal shell").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            switch shell {
            case .ainkrad:
                Text("Ainkrad zsh")
            case .login(let reason):
                VStack(alignment: .leading, spacing: 0) {
                    Text(reason.map { "Login shell (\($0))" } ?? "Login shell")
                    Text("Re-run the install command on this machine to get the Ainkrad shell.")
                        .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("runner-terminal-shell")
    }

    private var who: some View {
        card("Who may use it") {
            let people = (model.host.runnerHost?.people() ?? []).compactMap { p -> (RunnerPerson, String)? in
                RunnerFacts.access(p.scopes).map { (p, $0) }
            }
            ForEach(people, id: \.0.id) { p, words in
                HStack(spacing: Space.s3) {
                    Image(systemName: p.platform?.lowercased().contains("ios") == true ? "iphone" : "laptopcomputer")
                        .foregroundStyle(palette.text2).frame(width: Space.s5).accessibilityHidden(true)
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
        }
    }

    private var actions: some View {
        card("Actions") {
            VStack(spacing: Space.s2) {
                action("Start an AI session here", "bubble.left", disabled: off || !facts.agentsOn) {
                    model.host.runnerHost?.startAgent(on: runner.id)
                }
                .help(
                    off
                        ? unavailable ?? ""
                        : facts.agentsOn ? "Start an AI session on \(runner.name)" : "AI sessions are off here")
                action("Rename", "pencil", disabled: false) { model.confirmRename(runner) }
                    .help("Give \(runner.name) another name")
                action("Revoke runner…", "trash", disabled: false, danger: true) { model.confirmRevoke(runner) }
                    .help("Stop \(runner.name) and remove it from your Core")
            }
        }
    }

    /// Why the header's actions are off right now, for their tooltips.
    private var unavailable: String? {
        if off { return "Not available while \(runner.name) is offline" }
        if busy { return "New terminals are refused while \(runner.name) is over its load limit" }
        return nil
    }

    private func action(
        _ title: String, _ symbol: String, disabled: Bool, danger: Bool = false, run: @escaping () -> Void
    ) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(CoreButtonStyle(danger ? .quietDanger : .secondary))
        .disabled(disabled)
    }
}
