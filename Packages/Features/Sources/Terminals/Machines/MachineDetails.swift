import AppKit
import CoreUI
import SwiftUI

/// A machine's AI tools: one tag each, ready with its version, installing with its progress, or missing. Ainkrad installs and
/// updates them by itself; when a pinned tool is still missing and the session is not elevated, one button installs them all
/// (Touch ID once). Antigravity has no download Ainkrad may fetch, so its tag says how to get it.
struct MachineTools: View {
    let model: TerminalsModel
    let runner: RunnerItem
    @Environment(\.corePalette) private var palette

    private var down: Bool { [.offline, .notAnswering].contains(MachineStatus(runner)) }
    private var failed: ToolInstall? {
        model.installs[runner.id]?.values.sorted { $0.tool < $1.tool }.first { $0.state == .failed }
    }
    /// The pinned tools still missing with nothing installing them: what the Install button would ask for.
    private var missing: String? {
        guard !down, model.runningInstall(runner.id) == nil, RunnerFacts(runner: runner).agentsOn else { return nil }
        return AutoInstall.missing(runner)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("AI tools").coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(palette.text2)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: Space.s2) {
                ForEach(RunnerFacts.aiTools, id: \.key) { t in tag(t.key, t.name) }
            }
            if let failed {
                Label(
                    "Could not install \(RunnerTools.name(failed.tool)). \(failed.reason ?? "It is tried again when the machine restarts.")",
                    systemImage: "exclamationmark.triangle"
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.tone(.warn).ink)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Space.s3) {
                Text("Ainkrad installs and updates these by itself.").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(palette.text2)
                if let missing, !model.host.isElevated {
                    Button("Install \(missing) now") { Task { await model.installMissing(runner) } }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        .keyboardShortcut("i", modifiers: .command).environment(\.coreKeycap, "⌘I")
                        .help("Install \(missing) on \(model.machineName(runner)) now. Needs Touch ID once (⌘I)")
                }
            }
        }
        .accessibilityIdentifier("machine-tools")
    }

    @ViewBuilder private func tag(_ key: String, _ name: String) -> some View {
        let inst = model.installs[runner.id]?[key]
        if let inst, inst.state == .running {
            HStack(spacing: Space.s2) {
                Text("Installing \(name)").foregroundStyle(palette.primary)
                CoreMeter(Double(inst.percent) / 100, label: "Installing \(name)").frame(width: Space.s8 + Space.s2)
            }
            .modifier(Tag(fill: palette.primary.opacity(0.14)))
            .help("\(inst.step.isEmpty ? "Installing" : inst.step) · \(inst.percent)%")
        } else if let v = runner.tools[key] {
            HStack(spacing: Space.s1 + 2) {
                Image(systemName: "checkmark").imageScale(.small).foregroundStyle(palette.tone(.run).ink)
                Text(name)
                if !v.isEmpty {
                    Text(v.split(separator: ".").prefix(2).joined(separator: ".")).foregroundStyle(palette.text2)
                }
            }
            .modifier(Tag(fill: GlassInk.well))
            .help("\(name) \(v) is ready")
            .accessibilityLabel("\(name) ready, version \(v)")
        } else if !down {
            Text(name).foregroundStyle(palette.text2)
                .modifier(Tag(fill: .clear))
                .help(
                    key == "agy"
                        ? "Antigravity is not installed. Ainkrad cannot download it: install it from Google on \(model.machineName(runner)), then it shows here."
                        : "\(name) is not installed yet. Ainkrad installs it by itself."
                )
                .accessibilityLabel("\(name) not installed")
        }
    }
}

private struct Tag: ViewModifier {
    let fill: Color
    func body(content: Content) -> some View {
        content.coreFont(size: MacTextSize.body, weight: .medium).lineLimit(1).fixedSize()
            .padding(.horizontal, Space.s3).frame(height: MacSize.controlMd)
            .background(fill, in: coreShape(Radius.control))
    }
}

/// Details, folded: the system, the versions, the home folder, what it offers and how many AI sessions at once. Rename and
/// remove are in the page's ⋯ menu.
struct MachineDetails: View {
    @Bindable var model: TerminalsModel
    let runner: RunnerItem
    @Binding var open: Bool
    @Environment(\.corePalette) private var palette

    private var facts: RunnerFacts { RunnerFacts(runner: runner) }
    private var off: Bool { MachineStatus(runner) == .offline }
    private var busyPolicy: Bool { model.policyBusy.contains(runner.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Button {
                withAnimation(Motion.out(Motion.ui)) { open.toggle() }
            } label: {
                Label("Details", systemImage: open ? "chevron.down" : "chevron.right")
            }
            .buttonStyle(CoreButtonStyle(.plain, size: .small))
            .keyboardShortcut("d", modifiers: [.command, .option]).environment(\.coreKeycap, "⌥⌘D")
            .help(open ? "Hide the details (⌥⌘D)" : "Show the system, versions, home folder and capacity (⌥⌘D)")
            if open {
                VStack(alignment: .leading, spacing: Space.s4) {
                    card(grid)
                    if !runner.builtIn || runner.policy != nil { offers }
                }
                .transition(.opacity)
            }
        }
        .accessibilityIdentifier("machine-details")
    }

    private func card<C: View>(_ c: C) -> some View {
        c.padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).coreWell()
    }

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: Space.s6, verticalSpacing: Space.s2) {
            row("System", facts.system.map(Self.plainArch))
            GridRow {
                label("Runner version")
                HStack(spacing: Space.s2) {
                    Text(runner.version ?? "Not reported yet")
                    if facts.updateAvailable {
                        Button("Update available") { openUpdates() }
                            .buttonStyle(CoreButtonStyle(.plain, size: .small))
                            .help("Updates are in Settings, Updates")
                    }
                }
            }
            if let home = runner.home {
                GridRow {
                    label("Home folder")
                    HStack(spacing: Space.s2) {
                        Text(home).coreFont(size: MacTextSize.meta, design: .monospaced).lineLimit(1)
                            .truncationMode(.middle).textSelection(.enabled).help(home)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(home, forType: .string)
                        }
                        .buttonStyle(CoreButtonStyle(.plain, size: .small)).help("Copy the folder path")
                    }
                }
            }
            row("Runs as", facts.runsAs)
            if let shell = facts.terminalShell {
                switch shell {
                case .ainkrad: row("Terminal shell", "Ainkrad zsh")
                case .login(let reason):
                    row(
                        "Terminal shell",
                        "Login shell" + (reason.map { " (\($0))" } ?? "") + ". Run the install command again on it.")
                }
            }
            row("Can use your accounts", facts.accountsAnswer)
            if let f = model.facts(runner.id), !f.toolchains.isEmpty {
                row("Toolchains", f.toolchains.joined(separator: ", "))
            }
            row("Other tools", otherTools)
            row(
                "Connected since",
                runner.connectedSince.map { $0.formatted(date: .abbreviated, time: .shortened) })
        }
    }

    /// "Ubuntu 24.04 x86_64" reads "Ubuntu 24.04, Intel" for people.
    static func plainArch(_ s: String) -> String {
        s.replacingOccurrences(of: " x86_64", with: ", Intel or AMD")
            .replacingOccurrences(of: " aarch64", with: ", ARM").replacingOccurrences(
                of: " arm64", with: ", Apple silicon")
    }

    private var otherTools: String? {
        let keys = RunnerTools.all.map(\.id).filter { k in !RunnerFacts.aiTools.contains { $0.key == k } }
        let have = keys.compactMap { k in runner.tools[k].map { "\(RunnerTools.name(k)) \($0)" } }
        return have.isEmpty ? nil : have.joined(separator: ", ")
    }

    private func label(_ s: String) -> some View {
        Text(s).foregroundStyle(palette.text2).gridColumnAlignment(.leading)
    }

    @ViewBuilder private func row(_ k: String, _ v: String?) -> some View {
        if let v {
            GridRow {
                label(k)
                Text(v).lineLimit(2).textSelection(.enabled)
            }
        }
    }

    /// What it offers, and how many AI sessions at once: the capacity setting.
    private var offers: some View {
        let p = runner.policy ?? RunnerPolicy(terminals: facts.terminalsOn, agents: facts.agentsOn, capacity: 2)
        return card(
            VStack(alignment: .leading, spacing: Space.s3) {
                if !model.hidesTerminals(runner) {
                    switchRow("Terminals", "Open a shell on it", p.terminals) { v in
                        Task { await model.setPolicy(runner, terminals: v) }
                    }
                }
                switchRow("AI sessions", "Claude, Codex, OpenCode and Antigravity can work on it", p.agents) { v in
                    Task { await model.setPolicy(runner, agents: v) }
                }
                if runner.policy != nil, p.agents {
                    HStack(spacing: Space.s3) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("AI sessions at the same time").coreFont(size: MacTextSize.body, weight: .medium)
                            Text("It restarts for a moment when this changes").coreFont(size: MacTextSize.meta)
                                .foregroundStyle(palette.text2)
                        }
                        Spacer(minLength: Space.s2)
                        CoreNumberStepper(value: p.capacity, in: 1...8, noun: "AI sessions at the same time") { n in
                            Task { await model.setPolicy(runner, capacity: n) }
                        }
                        .disabled(busyPolicy || off)
                    }
                    .accessibilityIdentifier("runner-capacity")
                }
                if let n = model.policyNote[runner.id] {
                    Label(n.text, systemImage: n.refused ? "exclamationmark.triangle" : "arrow.triangle.2.circlepath")
                        .coreFont(size: MacTextSize.meta)
                        .foregroundStyle(n.refused ? palette.tone(.warn).ink : palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("runner-policy-note")
                }
            })
    }

    private func switchRow(
        _ title: String, _ sub: String, _ on: Bool, set: @escaping @Sendable @MainActor (Bool) -> Void
    ) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).coreFont(size: MacTextSize.body, weight: .medium)
                Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            }
            Spacer(minLength: Space.s2)
            CoreSwitch("", isOn: Binding(get: { on }, set: set)).accessibilityLabel(title)
                .disabled(busyPolicy || off)
        }
    }

    private func openUpdates() {
        model.shell.settings.selected = "updates"
        model.shell.open(.settings)
    }
}
