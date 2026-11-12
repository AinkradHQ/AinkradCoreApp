import CoreUI
import SwiftUI

extension AddWizardView {
    /// A runner (or a device when the Core cannot make QR invites): the code, in the command, then the check code. The Core
    /// still wants the approver to compare it, and holds a code for 5 minutes.
    @ViewBuilder var typedConnect: some View {
        let t = model.typed
        VStack(alignment: .leading, spacing: Space.s3) {
            switch t?.stage {
            case .code(let p)?:
                typedCommand(p)
                checkLines(AddWizardWords.connectLines(invited: true, connected: nil, checked: false), busy: true)
                if let end = p.expiresAt {
                    Label {
                        Text("Valid for ") + Text(timerInterval: Date.now...max(end, .now), countsDown: true)
                            + Text(" · works once")
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                }
                Button("Cancel this code") { Task { await t?.reject() } }.buttonStyle(.corePlain)
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
                CoreNotice(symbol: "checkmark", title: "Connected", tone: .done)
            case .ended(let why)?:
                CoreNotice(
                    symbol: "xmark", title: why == "rejected" ? "The pairing was rejected." : "The code ran out."
                ) {
                    Button("Make a new code") { Task { await model.again() } }.buttonStyle(.coreSecondary)
                }
            default:
                HStack(spacing: Space.s2) {
                    CoreBusyBar().frame(maxWidth: Space.s8 * 4)
                    Text("Making the code…").foregroundStyle(palette.text2)
                }
            }
            if let e = t?.error { CoreNotice(symbol: "exclamationmark.triangle", title: e, tone: .fail) }
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
            command(
                AddWizardPlan.linuxCommand(
                    core: model.coreURL, code: code, terminals: model.terminals, agents: model.agents))
        case .macRunner:
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

    // MARK: 5 settings

    var settings: some View {
        let live = model.runnerSettings
        return VStack(alignment: .leading, spacing: Space.s2) {
            if let r = live, r.editable {
                GlassToggleTile(
                    "Terminals", sub: "Open a shell on this runner.", symbol: "terminal",
                    isOn: Binding(get: { r.terminals }, set: { v in model.changeRunner(r.id, terminals: v) }),
                    fill: true
                )
                .disabled(r.busy)
                GlassToggleTile(
                    "AI sessions", sub: "Let AI sessions work here.", symbol: "sparkles",
                    isOn: Binding(get: { r.agents }, set: { v in model.changeRunner(r.id, agents: v) }), fill: true
                )
                .disabled(r.busy)
                if r.agents {
                    settingRow("AI sessions at the same time", "More sessions use more memory.") {
                        HStack(spacing: Space.s2) {
                            Button {
                                model.changeRunner(r.id, capacity: r.capacity - 1)
                            } label: {
                                Image(systemName: "minus")
                            }
                            .disabled(r.capacity <= 1 || r.busy).help("Fewer AI sessions at the same time")
                            .accessibilityLabel("Fewer AI sessions")
                            Text("\(r.capacity)").fontWeight(.semibold).monospacedDigit().frame(minWidth: Space.s6)
                            Button {
                                model.changeRunner(r.id, capacity: r.capacity + 1)
                            } label: {
                                Image(systemName: "plus")
                            }
                            .disabled(r.capacity >= 8 || r.busy).help("More AI sessions at the same time")
                            .accessibilityLabel("More AI sessions")
                        }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    }
                }
                if let note = r.note {
                    Label(
                        note, systemImage: r.noteIsRefusal ? "exclamationmark.triangle" : "arrow.triangle.2.circlepath"
                    )
                    .coreFont(size: MacTextSize.meta)
                    .foregroundStyle(r.noteIsRefusal ? palette.tone(.warn).ink : palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                settingRow("Terminals", "Open a shell on this runner.") {
                    Text(model.terminals ? "On" : "Off").foregroundStyle(palette.text2)
                }
                settingRow("AI sessions", "Let AI sessions work here.") {
                    Text(model.agents ? "On" : "Off").foregroundStyle(palette.text2)
                }
                Text(
                    live == nil
                        ? "The runner is not in the list yet. Change these later on its page."
                        : "This runner is too old to change these from the app. Update it first."
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func settingRow<T: View>(_ title: String, _ detail: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).fontWeight(.semibold)
                Text(detail).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(Space.s3).background(palette.uDim, in: coreShape(Radius.cardMac))
    }
}
