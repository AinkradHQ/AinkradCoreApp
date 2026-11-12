import AppKit
import CoreUI
import SwiftUI

/// The words of the Add flow (n17), out of the view so the tests pin them.
enum AddWizardWords {
    @MainActor static func title(_ m: AddWizardModel) -> String {
        switch m.step {
        case .what: "What do you want to add?"
        case .install:
            switch m.kind {
            case .phone: "Get Ainkrad on your iPhone"
            case .mac: "Get Ainkrad Core on the other Mac"
            case .linuxRunner: "Install the runner on your Linux server"
            case .macRunner: "Install the runner on the other Mac"
            case nil: "Install"
            }
        case .connect: m.connectedYet ? "Connected" : "Waiting for the new device…"
        case .access: "What may it do?"
        case .settings: "Runner settings"
        case .done: "\(m.connected?.name ?? m.name) is ready"
        }
    }

    @MainActor static func sub(_ m: AddWizardModel) -> String {
        switch m.step {
        case .what: "Pick one. Ainkrad shows you the rest, step by step."
        case .install:
            switch m.kind {
            case .phone: "The iPhone app is not out yet."
            case .mac: "Scan with the other Mac’s camera, or open the link there."
            case .linuxRunner where m.usesRunnerInvite:
                "Run this one command on the server. It installs the runner and connects it. No code to type."
            default: "Get the runner onto the machine, then choose what it offers."
            }
        case .connect:
            m.connectedYet
                ? "The new device answered."
                : m.usesRunnerInvite || m.usesInvite
                    ? "Nothing to type. The invite is the proof, and it works once."
                    : "Run the command there, then compare the check code here."
        case .access: "Pick the closest. You can change it later."
        case .settings: "How \(m.connected?.name ?? m.name) should work. You can change these later."
        case .done: "AI sessions and terminals can use it now."
        }
    }

    @MainActor static func next(_ m: AddWizardModel) -> String {
        switch m.step {
        case .install: m.kind?.isRunner == true ? "I ran it" : "Installed"
        case .access: "Add"
        case .settings: "Add runner"
        default: "Next"
        }
    }

    @MainActor static func summary(_ m: AddWizardModel, _ d: DeviceInfo?) -> String {
        if m.kind?.isRunner == true {
            return "Runner · Terminals \(m.terminals ? "on" : "off") · AI sessions \(m.agents ? "on" : "off")"
        }
        return "\(m.kind?.title ?? "Device") · \(AccessPreset.matching(Set(d?.scopes ?? m.granted)).title)"
    }

    /// The three lines of the connect step: what is done, and the one being waited on.
    static func connectLines(invited: Bool, connected: String?, checked: Bool) -> [(text: String, done: Bool)] {
        [
            ("Invite created · 15 minutes", invited),
            (connected.map { "\($0) connected" } ?? "Waiting for the new device…", connected != nil),
            ("Connection checked", checked),
        ]
    }
}

extension AddWizardView {
    // MARK: 2 install

    @ViewBuilder var install: some View {
        switch model.kind {
        case .phone:
            VStack(spacing: Space.s2) {
                IconTile("iphone", hue: GlassInk.blue, size: 48)
                Text("Coming soon").coreFont(size: MacTextSize.title, weight: .semibold)
                Text(
                    "When it is ready, a QR here opens its App Store or TestFlight page. You can add a Mac or a runner now."
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: Space.s8 * 12)
            }
            .padding(Space.s5).frame(maxWidth: .infinity).background(palette.uDim, in: coreShape(Radius.cardMac))
        case .mac:
            HStack(alignment: .top, spacing: Space.s4) {
                QRImage(text: AddWizardPlan.macReleases.absoluteString).frame(width: Space.s8 * 5, height: Space.s8 * 5)
                    .accessibilityLabel("QR code for the download page")
                VStack(alignment: .leading, spacing: Space.s2) {
                    HStack(spacing: Space.s3) {
                        Image(systemName: "arrow.down.to.line").foregroundStyle(palette.text2).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Ainkrad Core for Mac (.dmg)").fontWeight(.semibold)
                            Text("From GitHub Releases · signed and notarized").coreFont(size: MacTextSize.meta)
                                .foregroundStyle(palette.text2)
                        }
                        Spacer(minLength: 0)
                        Button {
                            copy(AddWizardPlan.macReleases.absoluteString)
                        } label: {
                            Label("Copy link", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    }
                    .padding(Space.s3).background(palette.uDim, in: coreShape(Radius.cardMac))
                    CoreTextField("Name", placeholder: AddKind.mac.defaultName, text: $model.name)
                }
            }
        case .linuxRunner, .macRunner:
            if model.usesRunnerInvite { runnerCommand } else { typedRunnerInstall }
        case nil: EmptyView()
        }
    }

    func command(_ text: String, copied: Bool = false, copy run: (() -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Text(text).coreFont(size: MacTextSize.meta, design: .monospaced).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                if let run { run() } else { copy(text) }
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small))
        }
        .padding(Space.s3).background(palette.uDim, in: coreShape(Radius.control))
    }

    /// A Linux server with a runner invite: the one command, its countdown, and what it does.
    @ViewBuilder private var runnerCommand: some View {
        let m = model.runnerInvite
        VStack(alignment: .leading, spacing: Space.s3) {
            if let m, let text = m.command, m.live {
                command(text, copied: m.copied) { m.copy() }
                    .accessibilityHint("The command has a one-time secret; the copy is cleared after a minute.")
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Label {
                        Text("Valid for \(RunnerInviteModel.clock(m.secondsLeft(now: ctx.date))) · works once")
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    .onChange(of: m.secondsLeft(now: ctx.date)) { _, _ in m.tick(now: ctx.date) }
                }
                well {
                    Text("What happens").coreFont(size: MacTextSize.meta, weight: .semibold)
                    Text(
                        "1. Installs the runner and the tools AI sessions need.\n2. Connects to this Core with the invite.\n3. Starts by itself when the server starts."
                    )
                    .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                }
                DisclosureGroup("Advanced") {
                    Button("Use a typed code instead") { Task { await model.useTypedCode() } }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        .help("For a server where the command cannot run. Core then asks you to compare a check code.")
                        .padding(.top, Space.s2)
                }
                .foregroundStyle(palette.text2)
            } else if let m, m.phase == .expired || m.phase == .withdrawn {
                CoreNotice(
                    symbol: "clock", title: m.phase == .expired ? "The invite ran out." : "The invite was withdrawn."
                ) {
                    Button("Make a new invite") { Task { await model.again() } }.buttonStyle(.coreSecondary)
                }
            } else if let m, m.done {
                CoreNotice(symbol: "checkmark", title: "The runner connected.", tone: .done)
            } else if model.makeFailed {
                CoreNotice(symbol: "exclamationmark.triangle", title: "The invite was not made.") {
                    Button("Try again") { Task { await model.startConnect() } }.buttonStyle(.coreSecondary)
                }
            } else {
                HStack(spacing: Space.s2) {
                    CoreBusyBar().frame(maxWidth: Space.s8 * 4)
                    Text("Making the invite…").foregroundStyle(palette.text2)
                }
            }
            if let e = m?.error { CoreNotice(symbol: "exclamationmark.triangle", title: e, tone: .fail) }
        }
    }

    private var typedRunnerInstall: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Get the runner").fontWeight(.semibold)
                    Text("Download it from GitHub Releases onto the machine and unpack it.")
                        .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                }
                Spacer(minLength: 0)
                Button {
                    NSWorkspace.shared.open(AddWizardPlan.runnerReleases)
                } label: {
                    Label("Open releases", systemImage: "arrow.up.right")
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
            .padding(Space.s3).background(palette.uDim, in: coreShape(Radius.cardMac))
            CoreTextField("Name", placeholder: model.kind?.defaultName ?? "runner", text: $model.name)
            // fill: both tiles take the dialog's width, so their edges line up.
            GlassToggleTile(
                "Terminals", sub: "Open a shell on this runner.", symbol: "terminal", isOn: $model.terminals,
                fill: true)
            GlassToggleTile(
                "AI sessions", sub: "Let AI sessions work here.", symbol: "sparkles", isOn: $model.agents, fill: true)
        }
    }

    // MARK: 3 connect

    @ViewBuilder var connect: some View {
        if model.usesRunnerInvite {
            runnerWaiting
        } else if model.usesInvite {
            inviteConnect
        } else {
            typedConnect
        }
    }

    func checkLines(_ lines: [(text: String, done: Bool)], busy: Bool) -> some View {
        well {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                let current = !l.done && (i == 0 || lines[i - 1].done)
                Label {
                    Text(l.text).foregroundStyle(l.done || current ? palette.text : palette.text2)
                } icon: {
                    Image(systemName: l.done ? "checkmark.square.fill" : "square")
                        .foregroundStyle(l.done ? palette.tone(.done).ink : palette.text2)
                }
                .fontWeight(current ? .semibold : .regular)
            }
            if busy { CoreBusyBar().padding(.top, Space.s1) }
        }
        .accessibilityElement(children: .combine)
    }

    /// The runner invite's waiting screen: the three lines, then "Connected: name".
    private var runnerWaiting: some View {
        let m = model.runnerInvite
        let name: String? = if case .connected(let n)? = m?.phase { n } else { nil }
        return VStack(alignment: .leading, spacing: Space.s3) {
            checkLines(
                AddWizardWords.connectLines(invited: m?.invite != nil, connected: name, checked: name != nil),
                busy: m?.live == true)
            if let name {
                CoreNotice(symbol: "checkmark", title: "Connected: \(name)", tone: .done)
            } else if let m, m.phase == .expired || m.phase == .withdrawn {
                CoreNotice(
                    symbol: "clock", title: m.phase == .expired ? "The invite ran out." : "The invite was withdrawn."
                ) {
                    Button("Make a new invite") { Task { await model.again() } }.buttonStyle(.coreSecondary)
                }
            } else {
                Text("Run the command on the server. This window updates by itself.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            }
            if let e = m?.error { CoreNotice(symbol: "exclamationmark.triangle", title: e, tone: .fail) }
        }
        .task(id: m?.invite?.pairingID) {
            while !Task.isCancelled, model.step == .connect, !model.connectedYet, !model.ended {
                try? await Task.sleep(for: .seconds(2))
                await model.poll()
            }
        }
    }

    private var inviteConnect: some View {
        let m = model.invite
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s4) {
                Group {
                    if let invite = m?.invite, m?.used != true, m?.ended != true {
                        QRImage(text: invite.link.text)
                    } else {
                        coreShape(Radius.cardMac).fill(palette.uDim)
                            .overlay { if m?.invite == nil, !model.makeFailed { CoreBusyBar().padding(Space.s4) } }
                    }
                }
                .frame(width: Space.s8 * 5, height: Space.s8 * 5)
                .accessibilityIdentifier("invite-qr")
                VStack(alignment: .leading, spacing: Space.s3) {
                    checkLines(
                        AddWizardWords.connectLines(
                            invited: m?.invite != nil,
                            connected: m?.used == true ? (m?.invite?.name ?? model.name) : nil,
                            checked: m?.used == true),
                        busy: m?.invite != nil && m?.used != true && m?.ended != true)
                    if m?.invite != nil, m?.used != true, m?.ended != true {
                        Text("On the new Mac, open Ainkrad Core and scan this, or paste the link.")
                            .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            m?.copyLink()
                        } label: {
                            Label(m?.copied == true ? "Copied" : "Copy link", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        .accessibilityHint("The link has a one-time secret; the copy is cleared after a minute.")
                    }
                }
            }
            if m?.used == true {
                CoreNotice(symbol: "checkmark", title: "Connected: \(m?.invite?.name ?? model.name)", tone: .done)
            }
            if let e = m?.error { CoreNotice(symbol: "exclamationmark.triangle", title: e, tone: .fail) }
            if model.makeFailed {
                CoreNotice(symbol: "exclamationmark.triangle", title: "The invite was not made.") {
                    Button("Try again") { Task { await model.startConnect() } }.buttonStyle(.coreSecondary)
                }
            }
            if model.ended {
                CoreNotice(symbol: "xmark", title: "This invite was withdrawn.") {
                    Button("Make a new invite") { Task { await model.again() } }.buttonStyle(.coreSecondary)
                }
            }
        }
        .task(id: m?.invite) {
            while !Task.isCancelled, model.step == .connect, !model.connectedYet {
                try? await Task.sleep(for: .seconds(2))
                await model.poll()
            }
        }
    }
}
