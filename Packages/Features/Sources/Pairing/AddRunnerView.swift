import AppKit
import CoreUI
import Leyline
import Shell
import SwiftUI

/// Add a runner (mockup 13): Where, Allow, Connect, Done. The pick screen is four big cards; connecting shows live lines and says
/// in plain words why it failed.
struct AddRunnerView: View {
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
        CoreDialogPanel("", width: Space.s8 * 22) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                CoreStepper(Self.stepNames, at: stepNo)
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
        .background(WindowSharingGuard())
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
        case .pick: return "Add a runner"
        case .allow: return "What may it do?"
        case .failed: return "That did not work"
        case .done: return "\(name) is ready"
        case .connect:
            switch model.path {
            case .thisMac: return "Turning on this Mac"
            case .anotherMac: return "Open this on the other Mac"
            case .command: return "Paste this on the server"
            default: return model.picking ? "Which server?" : "Setting up \(model.setup?.hostName ?? "the server")"
            }
        }
    }

    private var subtitle: String {
        switch model.step {
        case .pick: "A runner is a computer that does work for you. Where is it?"
        case .allow: "You can change this later. It only works inside its own home folder."
        case .failed: "Nothing else was changed."
        case .done: "It can take work now. It will show up in Runners."
        case .connect:
            switch model.path {
            case .thisMac: "Just a moment."
            case .anotherMac: "It joins as a device. Turn on “Work for Core” there and it becomes a runner."
            case .command: "Open a terminal on the server, paste the line, press Return."
            default: model.picking ? "Pick a host from Leyline, or add a new one." : "Ainkrad is doing this over SSH. You can keep working."
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
                Button("Cancel", action: attemptClose).buttonStyle(.coreSecondary)
                Spacer()
                Text("Nothing changes until you finish").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                Spacer()
            case .allow:
                Button("Back") { model.back() }.buttonStyle(.coreSecondary)
                Spacer()
                Button("Continue") { Task { await model.next() } }.buttonStyle(CoreButtonStyle(.prominent))
                    .keyboardShortcut(.defaultAction)
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

    private var pick: some View {
        Grid(horizontalSpacing: Space.s3, verticalSpacing: Space.s3) {
            GridRow {
                card(.thisMac, "laptopcomputer", "This Mac", "One switch. Use the Mac you are on right now.") {
                    Text("Off").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                }
                card(.anotherMac, "macbook", "Another Mac", "Open a link on it. Scan a code or copy the link.") {
                    Text("A code and a link").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                }
            }
            GridRow {
                card(.ssh, "server.rack", "A server I can reach by SSH", "Pick a host you already added. Ainkrad does the rest.") {
                    HStack(spacing: Space.s1 + 2) {
                        ForEach(model.hosts.prefix(2)) { CoreChip($0.name, minWidth: 0).lineLimit(1) }
                        CoreChip("+ Add", minWidth: 0)
                    }
                }
                card(.command, "terminal", "A server by command", "Copy one line and paste it on the server.") {
                    Text("$ sudo sh -c \"$(curl -fsSL …").coreFont(size: MacTextSize.meta, design: .monospaced)
                        .foregroundStyle(palette.text2).lineLimit(1)
                }
            }
        }
    }

    private func card<V: View>(
        _ p: AddRunnerModel.Path, _ symbol: String, _ title: String, _ text: String, @ViewBuilder visual: () -> V
    ) -> some View {
        Button {
            model.choose(p)
        } label: {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s3) {
                    IconTile(symbol, hue: GlassInk.blue, size: Space.s8 + Space.s2)
                    Text(title).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Text(text).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                visual().padding(.top, Space.s1)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, minHeight: Space.s8 * 4 + Space.s2, alignment: .topLeading)
        }
        .buttonStyle(ChoiceCardStyle(selected: model.path == p))
        .accessibilityIdentifier("add-runner-\(p)")
    }

    // MARK: 2 allow

    private var allow: some View {
        VStack(spacing: Space.s2) {
            GlassToggleTile(
                "Open terminals", sub: "You and your AI can run commands on it.", symbol: "terminal", isOn: $model.terminals,
                fill: true)
            GlassToggleTile(
                "Run AI sessions", sub: "Claude, Codex, OpenCode and Antigravity can work on it.", symbol: "sparkles",
                isOn: $model.agents, fill: true)
            HStack(spacing: Space.s3) {
                IconTile("arrow.down.circle", hue: GlassInk.blue, size: Space.s8)
                VStack(alignment: .leading, spacing: 0) {
                    Text("AI tools are installed and kept up to date for you").coreFont(size: MacTextSize.body, weight: .medium)
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
        case nil: EmptyView()
        }
    }

    private func checkList(_ lines: [AddRunnerModel.Check]) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ForEach(lines) { c in
                HStack(spacing: Space.s3) {
                    IconTile(symbol(c.state), hue: hue(c.state), size: Space.s8 - Space.s2)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(c.state == .current ? c.working : c.title).coreFont(size: MacTextSize.body, weight: .medium)
                        if c.state != .pending {
                            Text(c.state == .bad ? "It said no" : c.note).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
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
        case .current: GlassInk.blue
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
                    Label("Valid for \(RunnerInviteModel.clock(m.secondsLeft(now: ctx.date))) · works once", systemImage: "clock")
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
                        Text("1. On the other Mac, scan the code or open the link in Ainkrad Core.\n2. Turn on “Work for Core” in This Mac.")
                            .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                        Button {
                            inv?.copyLink()
                        } label: {
                            Label(inv?.copied == true ? "Copied" : "Copy link", systemImage: inv?.copied == true ? "checkmark" : "doc.on.doc")
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
                    Text(model.failure?.title ?? "Something went wrong").coreFont(size: MacTextSize.title, weight: .semibold)
                    Text(model.failure?.text ?? "").foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
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
            summaryRow("server.rack", model.connectedName ?? "The runner", "Connected just now", badge: StateBadge("Idle", tone: .queue, symbol: "pause"))
            summaryRow("terminal", "Terminals and AI sessions", [model.terminals ? "terminals on" : nil, model.agents ? "AI sessions on" : nil].compactMap { $0 }.joined(separator: ", ").capitalizedFirst, badge: nil)
            if let tool = p?.installing {
                summaryRow("arrow.down.circle", "Installing \(tool)…", "Keep going. It finishes in the background.", badge: nil, meter: Double(p?.percent ?? 0) / 100)
            }
        }
    }

    private func summaryRow(_ symbol: String, _ title: String, _ text: String, badge: StateBadge?, meter: Double? = nil) -> some View {
        HStack(spacing: Space.s3) {
            IconTile(symbol, hue: GlassInk.blue, size: Space.s8)
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
