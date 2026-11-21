import AppKit
import CoreUI
import Leyline
import Shell
import SwiftUI

/// Add machine (mockup a-add): Where, Allow, Connect, Done. The pick screen is three rows with their keys (⌘1 This Mac, ⌘2 a
/// server or another Mac, ⌘3 a phone or iPad); connecting shows live lines and says in plain words why it failed.
struct AddRunnerView: View {
    @Environment(\.coreAccent) private var paneAccent
    let app: AppModel
    @Bindable var model: AddRunnerModel
    let close: () -> Void
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    static let stepNames = ["Where", "Allow", "Connect", "Done"]
    private var stepNo: Int {
        switch model.step {
        case .pick: 0
        case .allow: 1
        case .connect, .failed: 2
        case .done: 3
        }
    }

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 20) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if model.step != .pick && model.path != .onThatMac { CoreStepper(Self.stepNames, at: stepNo) }
                Group {
                    switch model.step {
                    case .pick: pick
                    case .allow: allow
                    case .connect: connect
                    case .failed: failed
                    case .done: done
                    }
                }
                .transition(reduce ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
                StepUpBanner(app: app)
                footer
            }
            .animation(reduce ? .easeOut(duration: Motion.hover) : Motion.out(Motion.ui), value: model.step)
        }
        .task(id: model.step) {
            // The connect screen looks at the Core every two seconds until it is connected or failed.
            while model.step == .connect, !Task.isCancelled {
                await model.poll()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .accessibilityIdentifier("add-runner")
    }

    // MARK: header and footer

    private var title: String {
        let name = model.connectedName ?? "The runner"
        switch model.step {
        case .pick:
            return model.serverPick
                ? (model.prefill.map { "Let \($0) do work" } ?? "A server or another Mac") : "Add a machine"
        case .allow: return "What may it do?"
        case .failed: return "That did not work"
        case .done: return "\(name) is ready"
        case .connect:
            switch model.path {
            case .thisMac: return "Turning on this Mac"
            case .onThatMac: return "On \(model.prefill ?? "that Mac")"
            case .anotherMac: return "Open this on the other Mac"
            case .command: return "Paste this on the server"
            default: return model.picking ? "Which server?" : "Setting up \(model.setup?.hostName ?? "the server")"
            }
        }
    }

    private var subtitle: String {
        switch model.step {
        case .pick: model.serverPick ? "How do you reach it?" : "Where is it?"
        case .allow: "You can change this later. It only works inside its own home folder."
        case .failed: "Nothing else was changed."
        case .done: "It can take work now. It shows in Machines."
        case .connect:
            switch model.path {
            case .thisMac: "Just a moment."
            case .onThatMac: "It already signs in, so it only needs its switch."
            case .anotherMac: "It joins your Core. Turn on Do work on this Mac there and it does work too."
            case .command: "Open a terminal on the server, paste the line, press Return."
            default:
                model.picking
                    ? "Pick a host from Leyline, or add a new one."
                    : "Ainkrad is doing this over SSH. You can keep working."
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).coreFont(size: MacTextSize.large + 6, weight: .semibold).accessibilityAddTraits(.isHeader)
                Text(subtitle).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s2)
            CoreIconButton(symbol: "xmark", label: "Close", action: attemptClose)
        }
    }

    private var footer: some View {
        HStack(spacing: Space.s2) {
            switch model.step {
            case .pick:
                if model.serverPick && model.prefill == nil {
                    Button("Back") { model.back() }.buttonStyle(.coreSecondary).coreShortcut(.cancel)
                } else {
                    Button("Cancel", action: attemptClose).buttonStyle(.coreSecondary).coreShortcut(.cancel)
                }
                Spacer()
                Text("Nothing changes until you pick one").coreFont(size: MacTextSize.meta).foregroundStyle(
                    palette.text2)
            case .allow:
                Button("Back") { model.back() }.buttonStyle(.coreSecondary)
                Spacer()
                Button("Continue") { Task { await model.next() } }.buttonStyle(CoreButtonStyle(.prominent))
                    .keyboardShortcut(.defaultAction)
            case .connect where model.path == .onThatMac:
                Button("Back") { model.back() }.buttonStyle(.coreSecondary).coreShortcut(.cancel)
                Spacer()
                Button("Done", action: close).buttonStyle(CoreButtonStyle(.prominent)).coreShortcut(.primary)
            case .connect:
                Button("Back") { model.back() }.buttonStyle(.coreSecondary)
                Spacer()
                if model.picking {
                    Button("Set up \(hostName)") { Task { await model.startSSH() } }
                        .buttonStyle(CoreButtonStyle(.prominent)).disabled(model.hostID == nil)
                } else {
                    Button("Waiting…") {}.buttonStyle(CoreButtonStyle(.prominent, busy: true)).disabled(true)
                }
            case .failed:
                Button("Back") { model.back() }.buttonStyle(.coreSecondary)
                Spacer()
                Button("Try again") { Task { await model.again() } }.buttonStyle(CoreButtonStyle(.prominent))
            case .done:
                Button("Add another") { Task { await model.startOver() } }.buttonStyle(.coreSecondary)
                Spacer()
                Button("Done", action: close).buttonStyle(CoreButtonStyle(.prominent)).keyboardShortcut(.defaultAction)
            }
        }
    }

    private var hostName: String { model.hosts.first { $0.id == model.hostID }?.name ?? "server" }

    private func attemptClose() { Task { if await model.requestClose() { close() } } }

    // MARK: 1 where

    @ViewBuilder private var pick: some View {
        VStack(spacing: Space.s2) {
            if !model.serverPick {
                let on = model.macRunner?.useThisMac == true && model.macRunner?.isAvailable == true
                row(
                    "1", "laptopcomputer", "This Mac",
                    on
                        ? "It already does work. Its switch is on its page in Machines."
                        : "Do work on this Mac while you are signed in. One switch.",
                    enabled: model.macRunner?.isAvailable == true && !on
                ) {
                    model.choose(.thisMac)
                    Task { await model.next() }
                }
                row("2", "cpu", "A server or another Mac", "Paste one line on it, or pick a host you reach by SSH.") {
                    model.serverPick = true
                }
                row("3", "iphone", "A phone or iPad", "Scan a code with it to sign in to your Core.") {
                    close()
                    app.openInviteDevice()
                }
            } else {
                let name = model.prefill
                let n = name == nil ? 0 : 1
                if let name {
                    row(
                        "1", "laptopcomputer", "Turn it on there",
                        "\(name) already signs in. Its switch does the rest; nothing to install."
                    ) { model.choose(.onThatMac) }
                }
                row(
                    "\(n + 1)", "terminal", "By command", "Copy one line and paste it in a terminal on \(name ?? "it")."
                ) {
                    model.choose(.command)
                }
                row(
                    "\(n + 2)", "server.rack", "A server I reach by SSH",
                    model.hosts.isEmpty
                        ? "Add a host in Leyline first, then Ainkrad does the rest."
                        : "Pick one of \(model.hosts.prefix(2).map(\.name).joined(separator: ", ")). Ainkrad does the rest."
                ) { model.choose(.ssh) }
                if name == nil {
                    row(
                        "\(n + 3)", "macbook", "Another Mac, new to your Core",
                        "Open a link on it, then turn on its switch."
                    ) {
                        model.choose(.anotherMac)
                    }
                }
            }
        }
    }

    /// One choice of the pick screen: tile, what it is, one line, and its key (⌘1, ⌘2…).
    private func row(
        _ key: String, _ symbol: String, _ title: String, _ text: String, enabled: Bool = true,
        run: @escaping () -> Void
    ) -> some View {
        Button(action: run) {
            HStack(spacing: Space.s4) {
                IconTile(symbol, hue: GlassInk.accent(paneAccent), size: Space.s8 + Space.s2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).coreFont(size: MacTextSize.body, weight: .semibold)
                    Text(text).coreFont(size: MacTextSize.body).foregroundStyle(palette.text2)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
                Spacer(minLength: Space.s2)
                CoreKeycap("⌘\(key)")
            }
            .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(ChoiceCardStyle(selected: false))
        .keyboardShortcut(KeyEquivalent(Character(key)), modifiers: .command)
        .disabled(!enabled).opacity(enabled ? 1 : 0.55)
        .help("\(title) (⌘\(key))")
        .accessibilityIdentifier("add-machine-\(title)")
    }

    /// A Mac that already signs in: the switch is on that Mac.
    private var onThatMac: some View {
        let name = model.prefill ?? "that Mac"
        return VStack(alignment: .leading, spacing: Space.s3) {
            ForEach(
                Array(
                    [
                        ("laptopcomputer", "On \(name), open Ainkrad Core."),
                        ("desktopcomputer", "Open Machines, then This Mac."),
                        ("power", "Turn on Do work on this Mac. It shows here under Does work."),
                    ].enumerated()), id: \.offset
            ) { _, s in
                HStack(spacing: Space.s3) {
                    IconTile(s.0, hue: GlassInk.slate, size: Space.s8 - Space.s2)
                    Text(s.1)
                }
            }
            Text("Ainkrad installs Claude, Codex and OpenCode on it by itself.").coreFont(size: MacTextSize.meta)
                .foregroundStyle(palette.text2)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).coreWell()
    }

    // MARK: 2 allow

    private var allow: some View {
        VStack(spacing: Space.s2) {
            GlassToggleTile(
                "Open terminals", sub: "You and your AI can run commands on it.", symbol: "terminal",
                isOn: $model.terminals,
                fill: true)
            GlassToggleTile(
                "Run AI sessions", sub: "Claude, Codex, OpenCode and Antigravity can work on it.", symbol: "sparkles",
                isOn: $model.agents, fill: true)
            HStack(spacing: Space.s3) {
                IconTile("arrow.down.circle", hue: GlassInk.accent(paneAccent), size: Space.s8)
                VStack(alignment: .leading, spacing: 0) {
                    Text("AI tools are installed and kept up to date for you").coreFont(
                        size: MacTextSize.body, weight: .medium)
                    Text("Ainkrad does it in the background, in versions it has tested, into the runner's own folder.")
                        .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).coreWell()
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: 3 connect

    @ViewBuilder private var connect: some View {
        switch model.path {
        case .thisMac: checkList(model.checks())
        case .ssh: if model.picking { hostPicker } else { sshProgress }
        case .command: commandCard
        case .anotherMac: anotherMac
        case .onThatMac: onThatMac
        case nil: EmptyView()
        }
    }

    private func checkList(_ lines: [AddRunnerModel.Check]) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ForEach(lines) { c in
                HStack(spacing: Space.s3) {
                    IconTile(symbol(c.state), hue: hue(c.state), size: Space.s8 - Space.s2)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(c.state == .current ? c.working : c.title).coreFont(
                            size: MacTextSize.body, weight: .medium)
                        if c.state != .pending {
                            Text(c.state == .bad ? "It said no" : c.note).coreFont(size: MacTextSize.meta)
                                .foregroundStyle(palette.text2)
                        }
                    }
                    Spacer(minLength: Space.s2)
                    if let p = c.progress { CoreMeter(p, label: c.working).frame(width: Space.s8 * 3) }
                }
                .opacity(c.state == .pending ? 0.55 : 1)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).coreWell()
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: lines.map(\.state.rawName))
    }

    private func symbol(_ s: AddRunnerModel.Check.State) -> String {
        switch s {
        case .done: "checkmark"
        case .current: "arrow.triangle.2.circlepath"
        case .pending: "clock"
        case .bad: "xmark"
        }
    }

    private func hue(_ s: AddRunnerModel.Check.State) -> Color {
        switch s {
        case .done: palette.tone(.run).ink
        case .current: GlassInk.accent(paneAccent)
        case .pending: GlassInk.slate
        case .bad: palette.tone(.fail).ink
        }
    }

    private var hostPicker: some View {
        VStack(spacing: Space.s2) {
            ForEach(model.hosts) { h in
                Button {
                    model.hostID = h.id
                } label: {
                    HStack(spacing: Space.s3) {
                        IconTile("server.rack", hue: GlassInk.slate, size: Space.s8 - Space.s2)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(h.name).coreFont(size: MacTextSize.body, weight: .semibold)
                            Text(h.isRunner ? "Already a runner" : h.detail).coreFont(size: MacTextSize.meta)
                                .foregroundStyle(palette.text2)
                        }
                        Spacer(minLength: 0)
                        if model.hostID == h.id { Image(systemName: "checkmark").foregroundStyle(palette.primary) }
                    }
                    .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(ChoiceCardStyle(selected: model.hostID == h.id))
                .disabled(h.isRunner)
                .accessibilityAddTraits(model.hostID == h.id ? .isSelected : [])
            }
            Button {
                model.addHost()
            } label: {
                Label("Add a host", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.s3)
            }
            .buttonStyle(ChoiceCardStyle(selected: false))
        }
    }

    private var sshProgress: some View { checkList(model.checks()) }

    private var commandCard: some View {
        let m = model.wizard?.runnerInvite
        return VStack(alignment: .leading, spacing: Space.s3) {
            if let m, let text = m.command, m.live {
                commandLine(text) { copy(text) }
                HStack(spacing: Space.s2) {
                    Text("When it asks for the code, paste it. Nothing shows as you paste.")
                        .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        m.copy()
                    } label: {
                        Label(m.copied ? "Copied" : "Copy code", systemImage: m.copied ? "checkmark" : "key")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Label(
                        "Valid for \(RunnerInviteModel.clock(m.secondsLeft(now: ctx.date))) · works once",
                        systemImage: "clock"
                    )
                    .monospacedDigit().coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    .onChange(of: m.secondsLeft(now: ctx.date)) { _, _ in m.tick(now: ctx.date) }
                }
                waiting("Waiting for it… this page updates by itself.")
            } else {
                HStack(spacing: Space.s2) {
                    CoreBusyBar().frame(maxWidth: Space.s8 * 4)
                    Text("Making the invite…").foregroundStyle(palette.text2)
                }
            }
        }
    }

    private var anotherMac: some View {
        let inv = model.wizard?.invite
        return VStack(alignment: .leading, spacing: Space.s3) {
            if let link = inv?.invite?.link {
                HStack(alignment: .top, spacing: Space.s4) {
                    QRImage(text: link.text).frame(width: Space.s8 * 5, height: Space.s8 * 5)
                        .accessibilityLabel("QR code for the invite")
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text(
                            "1. On the other Mac, scan the code or open the link in Ainkrad Core.\n2. There, open Machines, then This Mac, and turn on Do work on this Mac."
                        )
                        .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                        Button {
                            inv?.copyLink()
                        } label: {
                            Label(
                                inv?.copied == true ? "Copied" : "Copy link",
                                systemImage: inv?.copied == true ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    }
                }
                .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).coreWell()
                waiting("Waiting for the other Mac to say hello…")
            } else {
                HStack(spacing: Space.s2) {
                    CoreBusyBar().frame(maxWidth: Space.s8 * 4)
                    Text("Making the invite…").foregroundStyle(palette.text2)
                }
            }
        }
    }

    private func waiting(_ text: String) -> some View {
        HStack(spacing: Space.s2) {
            StateBadge("Waiting", tone: .done, symbol: "clock")
            Text(text).foregroundStyle(palette.text2)
        }
    }

    private func commandLine(_ text: String, copy run: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Text(text).coreFont(size: MacTextSize.meta, design: .monospaced).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: run) { Label("Copy", systemImage: "doc.on.doc") }
                .buttonStyle(CoreButtonStyle(.prominent, size: .small))
        }
        .padding(Space.s3).background(GlassInk.well, in: coreShape(Radius.control))
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: failed and done

    private var failed: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                IconTile("exclamationmark.triangle", hue: palette.tone(.fail).ink, size: Space.s8 + Space.s2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.failure?.title ?? "Something went wrong").coreFont(
                        size: MacTextSize.title, weight: .semibold)
                    Text(model.failure?.text ?? "").foregroundStyle(palette.text2).fixedSize(
                        horizontal: false, vertical: true)
                }
            }
            .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).coreWell()
            if model.path == .thisMac, model.macRunner?.state == .needsApproval {
                Button("Open Login Items") { model.macRunner?.openLoginItems() }.buttonStyle(.coreSecondary)
            }
            if model.path == .ssh, !model.checks().isEmpty { checkList(model.checks()) }
        }
    }

    private var done: some View {
        let p = model.progress
        return VStack(spacing: Space.s2) {
            summaryRow(
                "server.rack", model.connectedName ?? "The runner", "Connected just now",
                badge: StateBadge("Idle", tone: .queue, symbol: "pause"))
            summaryRow(
                "terminal", "Terminals and AI sessions",
                [model.terminals ? "terminals on" : nil, model.agents ? "AI sessions on" : nil].compactMap { $0 }
                    .joined(separator: ", ").capitalizedFirst, badge: nil)
            if let tool = p?.installing {
                summaryRow(
                    "arrow.down.circle", "Installing \(tool)…", "Keep going. It finishes in the background.",
                    badge: nil, meter: Double(p?.percent ?? 0) / 100)
            }
        }
    }

    private func summaryRow(_ symbol: String, _ title: String, _ text: String, badge: StateBadge?, meter: Double? = nil)
        -> some View
    {
        HStack(spacing: Space.s3) {
            IconTile(symbol, hue: GlassInk.accent(paneAccent), size: Space.s8)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).coreFont(size: MacTextSize.body, weight: .medium)
                Text(text).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            }
            Spacer(minLength: Space.s2)
            if let meter { CoreMeter(meter, label: title).frame(width: Space.s8 * 4) }
            if let badge { badge }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).coreWell()
        .accessibilityElement(children: .combine)
    }
}

extension AddRunnerModel.Check.State {
    fileprivate var rawName: String {
        switch self {
        case .done: "done"
        case .current: "current"
        case .pending: "pending"
        case .bad: "bad"
        }
    }
}

extension String {
    fileprivate var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
