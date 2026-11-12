import AppKit
import CoreUI
import Shell
import SwiftUI

/// Add a device or a runner (N17): What → Install → (Access) → Connect → (Settings) → Done, one screen each.
struct AddWizardView: View {
    let app: AppModel
    @Bindable var model: AddWizardModel
    let close: () -> Void
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        DialogCard(title: title, width: Space.s8 * 21, close: attemptClose) {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text(sub).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                if model.steps.count > 1 { progress }
                Group {
                    switch model.step {
                    case .what: what
                    case .install: install
                    case .access: access
                    case .connect: connect
                    case .settings: settings
                    case .done: done
                    }
                }
                .transition(reduce ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
                StepUpBanner(app: app)
                footer
            }
            .coreFont(size: MacTextSize.body)
            .animation(.smooth(duration: 0.3), value: model.step)
        }
        .background(WindowSharingGuard())
        .accessibilityIdentifier("add-wizard")
    }

    private var title: String {
        switch model.step {
        case .what: "What do you want to add?"
        case .install:
            switch model.kind {
            case .phone: "Get Ainkrad on your iPhone"
            case .mac: "Get Ainkrad Core on the other Mac"
            case .linuxRunner: "Install the runner on your Linux server"
            case .macRunner: "Install the runner on the other Mac"
            case nil: "Install"
            }
        case .access: "What may it do?"
        case .connect: model.connectedYet ? "Connected" : "Waiting for the new device…"
        case .settings: "Runner settings"
        case .done: "\(model.connected?.name ?? model.name) is ready"
        }
    }

    private var sub: String {
        switch model.step {
        case .what: "Pick one. Ainkrad shows you the rest, step by step."
        case .install:
            model.kind == .phone
                ? "The iPhone app is not out yet."
                : model.kind?.isRunner == true
                    ? "Run this on the machine. It installs the runner and connects it to this Core."
                    : "Scan with the other Mac's camera, or open the link there."
        case .access: "Pick the closest. You can change it later."
        case .connect:
            model.usesRunnerInvite
                ? "Nothing to compare. The command has a one-time token and works for 15 minutes."
                : model.usesInvite
                    ? "Nothing to type. The QR is the proof, and it works once."
                    : "Type nothing on the new device but the command. Then compare the check code here."
        case .settings: "What this runner offers. Change it here, any time."
        case .done: "AI sessions and terminals can use it now."
        }
    }

    // MARK: pieces

    private var progress: some View {
        let all = model.steps
        let at = all.firstIndex(of: model.step) ?? 0
        return VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: 3) {
                ForEach(Array(all.enumerated()), id: \.offset) { i, _ in
                    coreShape(2).fill(i <= at ? palette.primary : palette.glassCardEdge).frame(height: 4)
                }
            }
            HStack(spacing: 3) {
                ForEach(Array(all.enumerated()), id: \.offset) { i, s in
                    Text("\(i + 1)  \(s.title)").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(i == at ? palette.text : palette.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(at + 1) of \(all.count): \(model.step.title)")
    }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) { c() }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.glassCard, in: coreShape(Radius.cardMac))
            .overlay { coreShape(Radius.cardMac).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
    }

    private func mark(_ symbol: String, _ tint: Color? = nil) -> some View {
        Image(systemName: symbol).foregroundStyle(tint ?? palette.primary).frame(width: 28, height: 28)
            .background((tint ?? palette.primary).opacity(0.15), in: coreShape(8)).accessibilityHidden(true)
    }

    private func command(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Text(text).coreFont(size: MacTextSize.meta, design: .monospaced).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Copy") { copy(text) }.buttonStyle(.coreSecondary)
        }
        .padding(Space.s3).background(.black.opacity(0.25), in: coreShape(Radius.control))
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: 1 what

    private var what: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s2), GridItem(.flexible())], spacing: Space.s2) {
            ForEach(AddKind.allCases, id: \.self) { k in
                Button {
                    model.choose(k)
                } label: {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        mark(k.symbol)
                        Text(k.title).fontWeight(.semibold)
                        Text(k.blurb).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Space.s3).frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                    .background(palette.glassCard, in: coreShape(Radius.cardMac))
                    .overlay {
                        coreShape(Radius.cardMac).strokeBorder(
                            model.kind == k ? palette.primary : palette.glassCardEdge,
                            lineWidth: model.kind == k ? 1.5 : 1)
                    }
                    .contentShape(coreShape(Radius.cardMac))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.kind == k ? .isSelected : [])
                .accessibilityIdentifier("add-kind-\(k)")
            }
        }
    }

    // MARK: 2 install

    @ViewBuilder private var install: some View {
        switch model.kind {
        case .phone:
            card {
                HStack(spacing: Space.s3) {
                    mark("iphone")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Coming soon").fontWeight(.semibold)
                        Text(
                            "When it is ready, a QR here opens its App Store or TestFlight page. You can add a Mac or a runner now."
                        )
                        .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .mac:
            HStack(alignment: .top, spacing: Space.s4) {
                QRImage(text: AddWizardPlan.macReleases.absoluteString).frame(width: Space.s8 * 5, height: Space.s8 * 5)
                    .accessibilityLabel("QR code for the download page")
                VStack(alignment: .leading, spacing: Space.s2) {
                    card {
                        HStack(spacing: Space.s3) {
                            mark("arrow.down.circle")
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Ainkrad Core for Mac (.dmg)").fontWeight(.semibold)
                                Text("From GitHub Releases · signed and notarized").foregroundStyle(palette.text2)
                            }
                            Spacer(minLength: 0)
                            Button("Copy link") { copy(AddWizardPlan.macReleases.absoluteString) }.buttonStyle(
                                .coreSecondary)
                        }
                    }
                    card {
                        HStack(spacing: Space.s3) {
                            mark("terminal", palette.text2)
                            VStack(alignment: .leading, spacing: 0) {
                                Text("brew install --cask ainkrad-core").fontWeight(.semibold)
                                Text("Coming soon").foregroundStyle(palette.text2)
                            }
                        }
                    }
                    .opacity(0.6)
                }
            }
        case .linuxRunner, .macRunner:
            runnerInstall
        case nil: EmptyView()
        }
    }

    @ViewBuilder private var runnerInstall: some View {
        if model.usesRunnerInvite {
            card {
                HStack(spacing: Space.s3) {
                    mark("terminal")
                    VStack(alignment: .leading, spacing: 0) {
                        Text("One command does it all").fontWeight(.semibold)
                        Text(
                            "On the next screen Core shows one command with a one-time token in it. Run it on the server with sudo. It installs the runner and connects it to this Core."
                        )
                        .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else {
            typedRunnerInstall
        }
    }

    private var typedRunnerInstall: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            card {
                HStack(spacing: Space.s3) {
                    mark("arrow.down.circle")
                    VStack(alignment: .leading, spacing: 0) {
                        Text("1. Get the runner").fontWeight(.semibold)
                        Text("Download it from GitHub Releases onto the machine and unpack it.")
                            .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button("Open releases") { NSWorkspace.shared.open(AddWizardPlan.runnerReleases) }
                        .buttonStyle(.coreSecondary)
                }
            }
            card {
                Text("2. Choose what it offers").fontWeight(.semibold)
                Toggle("Terminals (open a shell on this runner)", isOn: $model.terminals)
                Toggle("AI sessions (let AI sessions work here)", isOn: $model.agents)
                Text("Core shows the command in the next step, with these choices in it.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            }
            .toggleStyle(.switch)
        }
    }

    // MARK: 3 access

    private var access: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            CoreTextField("Name", placeholder: model.kind?.defaultName ?? "Device", text: $model.name)
            VStack(spacing: Space.s2) {
                ForEach(AccessPreset.choices, id: \.self) { p in presetRow(p) }
            }
            if model.preset == .full, model.onlyOneAdmin {
                Label(
                    "Recommended: you have only one admin device. A second one with Full control is a good backup.",
                    systemImage: "bell"
                )
                .foregroundStyle(palette.tone(.warn).ink).fixedSize(horizontal: false, vertical: true)
            }
            if !model.dropped.isEmpty {
                Label(
                    "This Mac does not hold \(model.dropped.joined(separator: ", ")), so it cannot hand it on.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(palette.tone(.warn).ink).fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("Advanced · separate switches") {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: Space.s2), GridItem(.flexible())], spacing: Space.s2
                ) {
                    ForEach(Array(ScopeText.all.enumerated()), id: \.element) { i, s in
                        ScopeToggle(
                            scope: s,
                            on: Binding(get: { model.scopes.contains(s) }, set: { model.setScope(s, $0) }),
                            locked: model.held.isEmpty || model.held.contains(s)
                                ? nil : "This Mac does not hold it, so it cannot hand it on.", index: i)
                    }
                }
                .padding(.top, Space.s2)
            }
        }
    }

    private func presetRow(_ p: AccessPreset) -> some View {
        let on = model.preset == p
        return Button {
            model.pick(p)
        } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: on ? "checkmark.square.fill" : "square").foregroundStyle(
                    on ? palette.primary : palette.text2)
                mark(p.symbol)
                VStack(alignment: .leading, spacing: 0) {
                    Text(p.title).fontWeight(.semibold)
                    Text(p.blurb).foregroundStyle(palette.text2)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .background(palette.glassCard, in: coreShape(Radius.cardMac))
            .overlay {
                coreShape(Radius.cardMac).strokeBorder(
                    on ? palette.primary : palette.glassCardEdge, lineWidth: on ? 1.5 : 1)
            }
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: 4 connect

    @ViewBuilder private var connect: some View {
        if model.usesRunnerInvite {
            runnerConnect
        } else if model.usesInvite {
            inviteConnect
        } else {
            typedConnect
        }
    }

    private var inviteConnect: some View {
        let m = model.invite
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s4) {
                Group {
                    if m?.used == true {
                        stamp("checkmark", "\(m?.invite?.name ?? model.name) is connected", palette.tone(.done).ink)
                    } else if m?.ended == true {
                        stamp("xmark", "This QR was withdrawn", palette.text2)
                    } else if let invite = m?.invite {
                        QRImage(text: invite.link.text)
                    } else {
                        coreShape(Radius.cardMac).fill(palette.glassCard).overlay { CoreBusyBar().padding(Space.s4) }
                    }
                }
                .frame(width: Space.s8 * 6, height: Space.s8 * 6)
                .accessibilityIdentifier("invite-qr")
                VStack(alignment: .leading, spacing: Space.s2) {
                    steps(
                        [
                            ("Invite created", m?.invite != nil),
                            ("Waiting for the new device…", m?.used == true),
                        ])
                    Text(
                        "On the new Mac, open Ainkrad Core and scan this QR, or paste the link. It works once and stays valid until a device uses it or you withdraw it."
                    )
                    .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                    if let invite = m?.invite, m?.used != true, m?.ended != true {
                        HStack(spacing: Space.s2) {
                            Button(m?.copied == true ? "Copied" : "Copy link") { m?.copyLink() }.buttonStyle(
                                .coreSecondary)
                            Button("Withdraw the invite") { Task { await m?.withdraw() } }
                                .buttonStyle(.coreSecondary).disabled(m?.busy == true)
                        }
                        .accessibilityHint("The link has a one-time secret; the copy is cleared after a minute.")
                        Text(invite.link.address).coreFont(size: MacTextSize.meta, design: .monospaced)
                            .foregroundStyle(palette.text2).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            if let e = m?.error {
                Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(palette.tone(.fail).ink)
            }
            if model.ended { Button("Make a new QR") { Task { await model.again() } }.buttonStyle(.coreSecondary) }
        }
        .task(id: m?.invite) {
            while !Task.isCancelled, model.step == .connect, !model.connectedYet {
                try? await Task.sleep(for: .seconds(2))
                await model.poll()
            }
        }
    }

    /// A Linux server with a runner invite: the command, a 15 minute countdown, and who answered.
    private var runnerConnect: some View {
        let m = model.runnerInvite
        return VStack(alignment: .leading, spacing: Space.s3) {
            if let m, let command = m.command, m.live {
                Text("Run this one command on the server:").foregroundStyle(palette.text2)
                command_(command, copied: m.copied) { m.copy() }
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    HStack(spacing: Space.s3) {
                        Label {
                            Text("Valid for \(RunnerInviteModel.clock(m.secondsLeft(now: ctx.date))) · works once")
                                .monospacedDigit()
                        } icon: {
                            Image(systemName: "clock")
                        }
                        .foregroundStyle(palette.text2)
                        .onChange(of: m.secondsLeft(now: ctx.date)) { _, _ in m.tick(now: ctx.date) }
                    }
                }
                HStack(spacing: Space.s2) {
                    CoreBusyBar().frame(maxWidth: Space.s8 * 4)
                    Text("Waiting for the runner…").fontWeight(.semibold)
                }
                Button("Withdraw the invite") { Task { await m.withdraw() } }.buttonStyle(.coreSecondary)
                DisclosureGroup("Advanced") {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text(
                            "A typed code, if the command cannot run there. Core then asks you to compare a check code."
                        )
                        .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                        Button("Use a typed code instead") { Task { await model.useTypedCode() } }
                            .buttonStyle(.coreSecondary)
                    }
                    .padding(.top, Space.s2)
                }
            } else if let m, case .connected(let name) = m.phase {
                stamp("checkmark", "Connected: \(name)", palette.tone(.done).ink).frame(height: Space.s8 * 3)
            } else if let m, m.phase == .expired || m.phase == .withdrawn {
                Text(m.phase == .expired ? "The invite ran out." : "The invite was withdrawn.")
                    .foregroundStyle(palette.text2)
                Button("Make a new invite") { Task { await model.again() } }.buttonStyle(.coreProminent)
            } else {
                HStack {
                    CoreBusyBar().frame(maxWidth: Space.s8 * 4)
                    Text("Making the invite…")
                }
            }
            if let e = m?.error {
                Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(palette.tone(.fail).ink)
            }
        }
        .task(id: m?.invite?.pairingID) {
            while !Task.isCancelled, model.step == .connect, !model.connectedYet, !model.ended {
                try? await Task.sleep(for: .seconds(2))
                await model.poll()
            }
        }
    }

    private func command_(_ text: String, copied: Bool, copy: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Text(text).coreFont(size: MacTextSize.meta, design: .monospaced).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(copied ? "Copied" : "Copy", action: copy).buttonStyle(.coreSecondary)
        }
        .padding(Space.s3).background(.black.opacity(0.25), in: coreShape(Radius.control))
        .accessibilityHint("The command has a one-time secret; the copy is cleared after a minute.")
    }

    private func stamp(_ symbol: String, _ words: String, _ ink: Color) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: symbol).coreFont(size: MacTextSize.large, weight: .semibold).foregroundStyle(ink)
            Text(words).fontWeight(.semibold).multilineTextAlignment(.center)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.glassCard, in: coreShape(Radius.cardMac))
    }

    private func steps(_ list: [(String, Bool)]) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ForEach(Array(list.enumerated()), id: \.offset) { _, s in
                HStack(spacing: Space.s2) {
                    Image(systemName: s.1 ? "checkmark.square.fill" : "square")
                        .foregroundStyle(s.1 ? palette.tone(.done).ink : palette.text2)
                    Text(s.0).foregroundStyle(s.1 ? palette.text2 : palette.text)
                }
            }
        }
    }

    /// A runner (or a device when the Core cannot make QR invites): the code, in the command, then the check code. The Core
    /// still wants the approver to compare it, and holds a code for 5 minutes (the invite's 15 minutes and no check code
    /// need a runner invite that Core does not have yet).
    @ViewBuilder private var typedConnect: some View {
        let t = model.typed
        VStack(alignment: .leading, spacing: Space.s3) {
            switch t?.stage {
            case .code(let p)?:
                typedCommand(p)
                HStack(spacing: Space.s2) {
                    CoreBusyBar().frame(maxWidth: Space.s8 * 4)
                    Text("Waiting for the new device…").fontWeight(.semibold)
                }
                if let end = p.expiresAt {
                    Label {
                        Text("Valid for ") + Text(timerInterval: Date.now...max(end, .now), countsDown: true)
                            + Text(" · works once")
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .foregroundStyle(palette.text2)
                }
                Button("Cancel this code") { Task { await t?.reject() } }.buttonStyle(.coreSecondary)
            case .claimed(let info)?:
                Text("The new device connected. Compare the check code with the one on its screen.")
                    .foregroundStyle(palette.text2)
                if let sas = info.sas, let t { SASView(sas: sas, matched: t.groupsMatching) }
                if let t {
                    CoreTextField(
                        "Type it here to confirm they match", placeholder: "XXXX-XXXX-XXXX-XXXX",
                        text: Bindable(t).typed, mono: true, autofocus: true
                    ) { if t.checkMatches { Task { await t.approve() } } }
                    HStack(spacing: Space.s2) {
                        Button("Reject") { Task { await t.reject() } }.buttonStyle(.coreSecondary)
                        Spacer(minLength: 0)
                        Button("Approve") { Task { await t.approve() } }.buttonStyle(.coreProminent)
                            .disabled(!t.checkMatches)
                    }
                }
            case .approved?:
                Label("Connected", systemImage: "checkmark").fontWeight(.semibold).foregroundStyle(
                    palette.tone(.done).ink)
            case .ended(let why)?:
                Text(why == "rejected" ? "The pairing was rejected." : "The code ran out.").foregroundStyle(
                    palette.text2)
                Button("Make a new code") { Task { await model.again() } }.buttonStyle(.coreProminent)
            default:
                HStack {
                    CoreBusyBar().frame(maxWidth: Space.s8 * 4)
                    Text("Making the code…")
                }
            }
            if let e = t?.error {
                Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(palette.tone(.fail).ink)
            }
        }
        .task(id: model.typed?.pairingID) {
            while !Task.isCancelled, model.step == .connect, !model.connectedYet {
                try? await Task.sleep(for: .seconds(2))
                await model.poll()
            }
        }
    }

    @ViewBuilder private func typedCommand(_ p: NewPairing) -> some View {
        let code = AddDeviceView.shown(p.code)
        switch model.kind {
        case .linuxRunner:
            Text("Run this one command in the unpacked runner folder:").foregroundStyle(palette.text2)
            command(
                AddWizardPlan.linuxCommand(
                    core: model.coreURL, code: code, terminals: model.terminals, agents: model.agents))
        case .macRunner:
            Text("Run these on the Mac, one after the other:").foregroundStyle(palette.text2)
            ForEach(
                AddWizardPlan.macCommands(
                    core: model.coreURL, code: code, terminals: model.terminals, agents: model.agents),
                id: \.self
            ) { command($0) }
        default:
            Text("On the new device choose Connect to a Core, then enter this code:").foregroundStyle(palette.text2)
            command(code)
        }
    }

    // MARK: 5 settings, 6 done

    private var settings: some View {
        let live = model.runnerSettings
        return VStack(alignment: .leading, spacing: Space.s2) {
            if let r = live, r.editable {
                GlassToggleTile(
                    "Terminals", sub: "Open a shell on this runner.", symbol: "terminal",
                    isOn: Binding(
                        get: { r.terminals },
                        set: { v in model.changeRunner(r.id, terminals: v) }),
                    fill: true
                )
                .disabled(r.busy)
                GlassToggleTile(
                    "AI sessions", sub: "Let AI sessions work here.", symbol: "sparkles",
                    isOn: Binding(
                        get: { r.agents },
                        set: { v in model.changeRunner(r.id, agents: v) }),
                    fill: true
                )
                .disabled(r.busy)
                if r.agents {
                    card {
                        HStack(spacing: Space.s3) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("AI sessions at the same time").fontWeight(.semibold)
                                Text("More sessions use more memory.").foregroundStyle(palette.text2)
                            }
                            Spacer(minLength: 0)
                            Button {
                                model.changeRunner(r.id, capacity: r.capacity - 1)
                            } label: {
                                Image(systemName: "minus")
                            }
                            .buttonStyle(.coreSecondary).disabled(r.capacity <= 1 || r.busy)
                            .accessibilityLabel("Fewer AI sessions")
                            Text("\(r.capacity)").fontWeight(.semibold).monospacedDigit().frame(minWidth: 20)
                            Button {
                                model.changeRunner(r.id, capacity: r.capacity + 1)
                            } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.coreSecondary).disabled(r.capacity >= 8 || r.busy)
                            .accessibilityLabel("More AI sessions")
                        }
                    }
                }
                if let note = r.note {
                    Label(
                        note, systemImage: r.noteIsRefusal ? "exclamationmark.triangle" : "arrow.triangle.2.circlepath"
                    )
                    .foregroundStyle(r.noteIsRefusal ? palette.tone(.warn).ink : palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Text(
                    "Each change asks for Touch ID and the runner restarts for a moment. You can change these later on the runner's page."
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                settingRow("Terminals", model.terminals ? "On" : "Off", "Open a shell on this runner.")
                settingRow("AI sessions", model.agents ? "On" : "Off", "Let AI sessions work here.")
                Text(
                    live == nil
                        ? "The runner is not in the list yet. Change these later on its page."
                        : "This runner is too old to change these from the app. Update it first, or change how it starts on the machine."
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).fixedSize(
                    horizontal: false, vertical: true)
            }
        }
    }

    private func settingRow(_ title: String, _ value: String, _ detail: String) -> some View {
        card {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).fontWeight(.semibold)
                    Text(detail).foregroundStyle(palette.text2)
                }
                Spacer(minLength: 0)
                Text(value).foregroundStyle(palette.text2)
            }
        }
    }

    private var done: some View {
        let d = model.connected
        return VStack(alignment: .leading, spacing: Space.s3) {
            card {
                HStack(spacing: Space.s3) {
                    mark(model.kind?.symbol ?? "checkmark")
                    VStack(alignment: .leading, spacing: 0) {
                        Text(d?.name ?? model.name).fontWeight(.semibold)
                        Text(summary(d)).foregroundStyle(palette.text2)
                    }
                    Spacer(minLength: 0)
                    Label("Online", systemImage: "checkmark.circle").foregroundStyle(palette.tone(.done).ink)
                }
            }
            if model.kind?.isRunner == true, d != nil {
                HStack(spacing: Space.s2) {
                    Button("Test it") { Task { await model.test() } }.buttonStyle(.coreSecondary).disabled(
                        model.testing)
                    Text(model.testLine ?? "Sends a small test job and shows how fast it answers.").foregroundStyle(
                        palette.text2)
                }
            }
        }
        .task { await model.findConnected() }
    }

    private func summary(_ d: DeviceInfo?) -> String {
        let scopes = d?.scopes ?? model.granted
        if model.kind?.isRunner == true {
            return "Runner · Terminals \(model.terminals ? "on" : "off") · AI sessions \(model.agents ? "on" : "off")"
        }
        return "\(model.kind?.title ?? "Device") · \(AccessPreset.matching(Set(scopes)).title)"
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: Space.s2) {
            if model.step == .done {
                Button("Add another") { model.step = .what }.buttonStyle(.coreSecondary)
                Spacer(minLength: 0)
                Button("Done", action: attemptClose).buttonStyle(.coreProminent).coreShortcut(.primary)
            } else {
                if model.step == .what || (model.step == .install && model.kind == nil) {
                    Button("Cancel", action: attemptClose).buttonStyle(.coreSecondary).coreShortcut(.cancel)
                } else {
                    Button("Back") { model.back() }.buttonStyle(.coreSecondary)
                }
                Spacer(minLength: 0)
                if model.step == .install && model.kind == .phone {
                    Button("Pick something else") { model.step = .what }.buttonStyle(.coreProminent)
                } else {
                    Button(nextTitle) { Task { await model.next() } }.buttonStyle(.coreProminent)
                        .coreShortcut(.primary).disabled(!model.canGoNext)
                }
            }
        }
    }

    private var nextTitle: String {
        switch model.step {
        case .install:
            model.usesRunnerInvite ? "Show the command" : model.kind?.isRunner == true ? "I ran it" : "Installed"
        case .access: "Add"
        case .settings: "Next"
        default: "Next"
        }
    }

    private func attemptClose() {
        Task { if await model.requestClose() { close() } }
    }
}
