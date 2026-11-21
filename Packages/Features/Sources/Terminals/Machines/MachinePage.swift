import AppKit
import CoreUI
import SwiftUI

/// One machine that does work (Machines review, mockups a-detail and a-broken): what runs on it now, how busy it is, its AI
/// tools, and the rest folded under Details. An offline machine first says when and why, with the command to copy and
/// Check again. Keys: esc back, ⌘T new terminal here, ⌘⌫ remove, ⌘C copy the command, ⏎ check again (offline).
struct MachinePage: View {
    @Bindable var model: TerminalsModel
    let runner: RunnerItem
    @Environment(\.corePalette) var palette
    @Environment(\.coreAccent) private var paneAccent
    @State private var details = false
    @State private var checking = false

    var status: MachineStatus { MachineStatus(runner) }
    var down: Bool { status == .offline || status == .notAnswering }
    var name: String { model.machineName(runner) }
    var isMac: Bool { model.icon(runner) == "laptopcomputer" }
    private var work: [RunnerWork] { model.work(on: runner.id) }
    private var terminals: [TerminalItem] { model.terminals(on: runner.id) }
    private var jobs: [HardwareItem.Job] { model.hardware[runner.id]?.jobs ?? [] }
    var canTerminal: Bool { !down && RunnerStatus(runner) != .busy && runner.hasPty && !model.hidesTerminals(runner) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            hero
            if down { offlineCard }
            if runner.id == model.thisMacID, let mac = model.host.runnerHost?.thisMacWork() { mac }
            running
            if !down { load }
            MachineTools(model: model, runner: runner)
            MachineDetails(model: model, runner: runner, open: $details)
        }
        .coreFont(size: MacTextSize.body)
        .accessibilityIdentifier("machine-page")
    }

    // MARK: header

    private var kind: String {
        if runner.builtIn { return "Inside your Core" }
        if runner.id == model.thisMacID { return "The Mac you are on" }
        let os = (runner.os ?? "").lowercased()
        return isMac ? "Mac" : os.contains("linux") || os.isEmpty ? "Linux server" : (runner.osPretty ?? "Server")
    }

    private var heroLine: String {
        if status == .offline {
            return kind + (runner.lastSeen.map { " · offline since \(Machines.when($0))" } ?? " · offline")
        }
        let up = runner.connectedSince.map {
            "up "
                + $0.formatted(.relative(presentation: .numeric, unitsStyle: .wide)).replacingOccurrences(
                    of: " ago", with: "")
        }
        return [kind, up].compactMap { $0 }.joined(separator: " · ")
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: Space.s4) {
            IconTile(
                model.icon(runner), hue: MachineHue.of(status, palette, accent: GlassInk.accent(paneAccent)),
                size: Space.s8 + Space.s6)
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack(spacing: Space.s3) {
                    Text(name).coreFont(size: MacTextSize.large, weight: .bold).lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    StateBadge(status.rawValue, tone: status.tone, symbol: "circle")
                }
                Text(heroLine).foregroundStyle(palette.text2).lineLimit(1)
            }
            Spacer(minLength: Space.s3)
            if canTerminal {
                Button("New terminal here") { model.openNew(runner: runner.id) }
                    .buttonStyle(CoreButtonStyle(.secondary))
                    .keyboardShortcut("t", modifiers: .command).environment(\.coreKeycap, "⌘T")
                    .help("Open a terminal on \(name) (⌘T)")
            }
            more
        }
    }

    /// ⋯: start an AI session, pause, rename and remove. Remove also answers ⌘⌫ anywhere on the page.
    private var more: some View {
        let m = model
        let r = runner
        var items: [CoreDropdownItem] = []
        if !down, RunnerFacts(runner: r).agentsOn {
            items.append(
                CoreDropdownItem("Start an AI session here", symbol: "sparkles") {
                    m.host.runnerHost?.startAgent(on: r.id)
                })
        }
        if let f = model.facts(r.id), !f.isCore, !down {
            if f.pausedNow {
                items.append(
                    CoreDropdownItem("Resume new work", symbol: "play") { Task { await m.pause(r.id, .resume) } })
            } else {
                items.append(
                    CoreDropdownItem("Pause for 1 hour", symbol: "pause") { Task { await m.pause(r.id, .hour) } })
                items.append(
                    CoreDropdownItem("Pause until tomorrow", symbol: "moon") { Task { await m.pause(r.id, .tomorrow) } }
                )
            }
        }
        if !r.builtIn {
            items.append(CoreDropdownItem("Rename…", symbol: "pencil") { m.confirmRename(r) })
            items.append(
                CoreDropdownItem("Remove…", symbol: "trash", destructive: true, note: "⌘⌫") { m.confirmRevoke(r) })
        }
        return HStack(spacing: 0) {
            CoreDropdown(items: items) {
                Image(systemName: "ellipsis").frame(width: MacSize.controlMd, height: MacSize.controlMd)
                    .background(GlassInk.well, in: coreShape(Radius.control))
                    .accessibilityLabel("More for \(name)")
            }
            .help("Start an AI session, pause, rename or remove \(name)")
            if !r.builtIn {
                // ⌘⌫ removes from the page itself; the menu item shows the key.
                Button("") { m.confirmRevoke(r) }.keyboardShortcut(.delete, modifiers: .command)
                    .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
            }
        }
    }

    // MARK: offline

    /// What to run on it when it stays offline; nil for a Mac, which has no service to restart by hand.
    private var command: String? { isMac || runner.builtIn ? nil : "sudo systemctl restart ainkrad-runner" }

    private var steps: [(String, String)] {
        if runner.id == model.thisMacID {
            return [("power", "Is Do work on this Mac on?"), ("arrow.clockwise", "Still offline? Restart it below")]
        }
        if isMac {
            return [
                ("power", "Is the Mac awake, with the lid open?"), ("wifi", "Is it on the network?"),
                ("laptopcomputer", "Still offline? Open Ainkrad on it and check Do work on this Mac is on"),
            ]
        }
        return [("power", "Is it switched on?"), ("wifi", "Is it on the network?")]
    }

    private var offlineCard: some View {
        let when = runner.lastSeen.map { " at \(Machines.when($0))" } ?? ""
        let title = status == .offline ? "\(name) stopped answering\(when)" : "\(name) missed its last check-ins"
        return HStack(alignment: .top, spacing: Space.s4) {
            IconTile("wifi.slash", hue: palette.tone(.fail).ink, size: Space.s8 + Space.s2)
            VStack(alignment: .leading, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).coreFont(size: MacTextSize.title, weight: .semibold)
                    Text("Your Core is fine. Work on \(name) waits and goes on when it is back.")
                        .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(steps, id: \.1) { s in step(s.0) { Text(s.1) } }
                if let command {
                    step("terminal") {
                        HStack(spacing: Space.s2) {
                            Text("Still offline? Restart the service on it:")
                            Text(command).coreFont(size: MacTextSize.meta, design: .monospaced).textSelection(.enabled)
                                .padding(.horizontal, Space.s2).padding(.vertical, Space.s1)
                                .background(GlassInk.well, in: coreShape(Radius.chip))
                        }
                    }
                }
                HStack(spacing: Space.s2) {
                    if let command {
                        Button("Copy command") { copy(command) }
                            .buttonStyle(CoreButtonStyle(.secondary))
                            .keyboardShortcut("c", modifiers: .command).environment(\.coreKeycap, "⌘C")
                            .help("Copy the restart command (⌘C)")
                    }
                    Button("Check again") { Task { await checkAgain() } }
                        .buttonStyle(CoreButtonStyle(.prominent, busy: checking))
                        .keyboardShortcut(.defaultAction).environment(\.coreKeycap, "⏎")
                        .help("Ask the Core whether \(name) is back (⏎)")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.tone(.fail).ink.opacity(0.1), in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("machine-offline")
    }

    private func step<C: View>(_ symbol: String, @ViewBuilder _ text: () -> C) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: symbol).imageScale(.small).foregroundStyle(palette.text2)
                .frame(width: Space.s6, height: Space.s6).background(GlassInk.well, in: coreShape(Radius.chip))
                .accessibilityHidden(true)
            text()
        }
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        model.shell.showToast("Copied the command")
    }

    private func checkAgain() async {
        checking = true
        await model.reload()
        checking = false
        let back = model.runner(runner.id).map { MachineStatus($0) != .offline } ?? false
        model.shell.showToast(back ? "\(name) is back" : "\(name) is still offline", kind: back ? .ok : .info)
    }

    // MARK: running now

    private var running: some View {
        section(down ? "Waiting for it" : "Running now") {
            VStack(spacing: Space.s2) {
                ForEach(Array(work.enumerated()), id: \.element.id) { i, w in
                    workRow(
                        "sparkles", w.title, w.detail, primary: i == 0 && !down,
                        open: down ? nil : { model.host.runnerHost?.openAgent(w.id) })
                }
                ForEach(jobs) { j in
                    workRow(
                        "hammer", j.label, "Job · started " + j.startedAt.formatted(.relative(presentation: .named)))
                }
                ForEach(terminals.prefix(6)) { t in
                    workRow(
                        "terminal", terminalName(t), terminalLine(t),
                        primary: work.isEmpty && t.id == terminals.first?.id,
                        open: down ? nil : { model.openTerminal(t.id, attach: false) })
                }
                if terminals.count > 6 {
                    Text("and \(terminals.count - 6) more terminals").foregroundStyle(palette.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if work.isEmpty && jobs.isEmpty && terminals.isEmpty {
                    Text(down ? "Nothing waits for it." : "Nothing is running here.").foregroundStyle(palette.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func terminalName(_ t: TerminalItem) -> String {
        model.shell.tabNames["terminal-\(t.id)"] ?? (t.isReal ? "Real shell" : "Terminal")
    }

    private func terminalLine(_ t: TerminalItem) -> String {
        if down { return "Terminal · waits, nothing was lost" }
        let started = t.createdAt.map { "started " + $0.formatted(.relative(presentation: .named)) }
        let who =
            t.attached == 0
            ? "nobody attached" : model.sessions[t.id]?.isAttached == true ? "you are attached" : "attached"
        return ["Terminal", started, who].compactMap { $0 }.joined(separator: " · ")
    }

    private func workRow(
        _ symbol: String, _ title: String, _ detail: String, primary: Bool = false, open: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: Space.s3) {
            IconTile(symbol, hue: GlassInk.slate, size: Space.s6 + Space.s1)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).coreFont(size: MacTextSize.body, weight: .medium).lineLimit(1)
                Text(detail).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            if let open {
                Button("Open", action: open).buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .modifier(PrimaryKey(on: primary && !down))
                    .help("Open \(title)" + (primary ? " (⏎)" : ""))
            }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coreWell()
        .accessibilityElement(children: .contain)
    }

    // MARK: load

    private var load: some View {
        section("Load") {
            HStack(spacing: Space.s4) {
                let b = model.busy(runner) ?? 0
                Text("\(Int((b * 100).rounded()))% busy").coreFont(size: MacTextSize.body, weight: .semibold)
                    .monospacedDigit().fixedSize()
                CoreMeter(b, low: b >= 0.85, label: "\(name) busy")
                Text(Machines.room(runner) ?? (RunnerStatus(runner) == .busy ? "Very busy: new work waits" : ""))
                    .foregroundStyle(palette.text2).lineLimit(1).fixedSize()
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .coreWell()
        }
    }

    func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(palette.text2)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

/// Return opens the first thing running, when the page has nothing else on Return.
private struct PrimaryKey: ViewModifier {
    let on: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if on {
            content.keyboardShortcut(.defaultAction).environment(\.coreKeycap, "⏎")
        } else {
            content
        }
    }
}
