import AppKit
import CoreUI
import SwiftUI

/// Step 2 (an API key, or a plan's sign-in) and step 3 (done) of Add an AI account. Never the raw terminal: the runner's
/// lines only sit behind "Show details". Answers are never sent for the person; only a code they paste.
extension AddAccountDialog {
    // MARK: 2a. API key

    var keyStep: some View {
        let prefix = chosen.flatMap { AddCards.keyStart($0).prefix }
        let hint = KeyHint.of(flow.key, prefix: prefix, name: name)
        let checking = flow.stepper.step == .checking
        let pasted = !flow.key.isEmpty
        let page = chosen.flatMap(AddCards.keyPage)
        let canAdd = flow.live(model) == .looksValid && !checking
        return VStack(spacing: Space.s4) {
            ConnPair(kind: logo, size: Space.s8 * 2 - Space.s2)
            head("Add your \(name) key", "Two steps. The key never leaves your Core.")
            VStack(spacing: Space.s2) {
                ConnCheckRow(
                    index: 1,
                    item: ConnSignInItem(
                        role: .open, title: "Make a key on \(name)",
                        detail: page.map(ConnSignIn.pageName) ?? "On \(name)'s website",
                        state: flow.keyOpened || pasted ? .done : .current),
                    trailing: openKeyPage(page, done: flow.keyOpened || pasted))
                ConnCheckRow(
                    index: 2,
                    item: ConnSignInItem(
                        role: .copy, title: "Paste it here", detail: nil, state: pasted ? .current : .todo),
                    detail: AnyView(keyField(hint)), trailing: EmptyView())
            }
            if checking {
                VStack(spacing: Space.s2) {
                    Text("Checking the key with \(name)…").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary)
                    CoreWorkingBar(width: Self.width - 2 * Space.s6)
                }
                .accessibilityElement(children: .combine)
            }
            if let e = flow.error { AccIssue(text: e).frame(maxWidth: .infinity, alignment: .leading) }
            AccNotice(notice: model.host.elevationNotice)
            footer(primary: (checking ? "Checking…" : "Add", add), enabled: canAdd, busy: checking)
        }
    }

    @ViewBuilder private func openKeyPage(_ page: URL?, done: Bool) -> some View {
        if let page, !done {
            Button("Open") {
                flow.keyOpened = true
                model.opener(page)
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small)).help("Open \(name) in your browser")
        }
    }

    private func keyField(_ hint: KeyHint) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            CoreSecureField(
                "", placeholder: "Paste the key", text: Binding(get: { flow.key }, set: { flow.key = $0 }),
                autofocus: true, onSubmit: add
            )
            .accessibilityLabel("\(name) key")
            .accessibilityIdentifier("account-key")
            Text(hint.words).coreFont(size: MacTextSize.meta)
                .foregroundStyle(hint == .looksRight ? GlassInk.ink(GlassInk.green) : GlassInk.secondary)
                .accessibilityIdentifier("account-key-hint")
        }
        .padding(.top, Space.s1)
    }

    private func add() {
        guard flow.live(model) == .looksValid, flow.stepper.step == .key else { return }
        Task { await flow.submitKey(model, settle: !reduce) }
    }

    // MARK: 2b. a plan's sign-in

    @ViewBuilder var signInStep: some View {
        if let c = flow.runners, model.signIn == nil, c.none {
            NoRunnerView(
                provider: name, choice: c, install: installOffer(c),
                openRunners: {
                    // Setup hides the desktop: the Runners app would open behind it. Back to the pick there.
                    if embedded { return flow.back(model) }
                    close()
                    model.openRunners()
                },
                back: { flow.back(model) })
        } else {
            signInChecklist
        }
    }

    /// The install that lets a runner sign in, when the Core can do it.
    private func installOffer(_ c: RunnerChoice) -> NoRunnerView.Install? {
        guard let p = chosen, let target = flow.installing ?? c.installTarget(harness: p.harness) else { return nil }
        let progress = model.installs["\(target.id)|\(p.harness)"]
        return NoRunnerView.Install(
            runner: target.name, progress: progress, waiting: flow.waitingRestart,
            running: flow.installing != nil || progress?.state == .running, note: flow.installNote,
            start: { Task { await flow.installThenSignIn(model, on: target) } })
    }

    private var signInChecklist: some View {
        let s = model.signIn
        let step = signInAt
        return VStack(spacing: Space.s4) {
            ConnPair(kind: logo, size: Space.s8 * 2 - Space.s2)
            head("Sign in with your \(name) plan", "This window moves on by itself.")
            VStack(spacing: Space.s2) {
                if let device = s?.deviceCode, flow.style(model) == .deviceCode {
                    deviceRows(device, step)
                } else {
                    codeRows(step)
                }
            }
            if step == .finishing { CoreWorkingBar(width: Self.width - 2 * Space.s6) }
            if case .failed(let why)? = s?.stage { AccIssue(text: why).frame(maxWidth: .infinity, alignment: .leading) }
            if AddCards.risky(flow.providerID ?? "") {
                Label(
                    "Uses your plan at your own risk. \(chosen.map(AddCards.who) ?? name)’s rules may not allow it.",
                    systemImage: "exclamationmark.triangle"
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            detailsDisclosure(s, step)
            if step == .failed {
                footer(primary: ("Try Again", { Task { await flow.retrySignIn(model) } }))
            } else {
                footer()
            }
        }
    }

    /// Where each line stands: 0 sign in, 1 the code, 2 finishing, 3 all done.
    private func at(_ step: SignInStep) -> Int {
        switch step {
        case .starting, .openURL, .failed: 0
        case .enterCode: 1
        case .finishing: 2
        case .done: 3
        }
    }

    private func check(_ i: Int, _ step: SignInStep) -> ConnCheck {
        let a = at(step)
        return a > i ? .done : a == i ? .current : .todo
    }

    /// Claude, Antigravity: sign in on the page we opened, paste the code it shows, finishing.
    @ViewBuilder private func codeRows(_ step: SignInStep) -> some View {
        let who = chosen.map(AddCards.who) ?? name
        let page = SignInStep.page(model.signIn)
        ConnCheckRow(
            index: 1,
            item: ConnSignInItem(
                role: .open, title: "Sign in to \(who)",
                detail: step == .starting ? "Getting the page ready…" : "We opened it in your browser",
                state: check(0, step)),
            trailing: openAgain(page, show: at(step) <= 1))
        ConnCheckRow(
            index: 2,
            item: ConnSignInItem(
                role: .copy, title: "Paste the code \(who) shows", detail: "After you sign in", state: check(1, step)),
            detail: step == .enterCode ? AnyView(codeField) : nil, trailing: EmptyView())
        finishingRow(step)
    }

    /// ChatGPT: copy the code Ainkrad shows, enter it on the page we opened, finishing.
    @ViewBuilder private func deviceRows(_ device: String, _ step: SignInStep) -> some View {
        let who = chosen.map(AddCards.who) ?? name
        let page = SignInStep.page(model.signIn)
        let a = at(step) == 0 && copied ? 1 : at(step)
        ConnCheckRow(
            index: 1,
            item: ConnSignInItem(role: .copy, title: "Copy this code", detail: nil, state: a > 0 ? .done : .current),
            detail: AnyView(
                Text(device).coreFont(size: MacTextSize.large, weight: .semibold, design: .monospaced)
                    .textSelection(.enabled)
                    .accessibilityLabel("Code \(device.map(String.init).joined(separator: " "))")),
            trailing: Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(device, forType: .string)
                copied = true
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small)).help("Copy the code"))
        ConnCheckRow(
            index: 2,
            item: ConnSignInItem(
                role: .open, title: "Enter it on the \(who) page we opened",
                detail: page.map(ConnSignIn.pageName), state: a > 1 ? .done : a == 1 ? .current : .todo),
            trailing: openAgain(page, show: at(step) <= 1))
        finishingRow(step)
    }

    private func finishingRow(_ step: SignInStep) -> some View {
        ConnCheckRow(
            index: 3,
            item: ConnSignInItem(
                role: .approve, title: "Finishing",
                detail: step == .finishing
                    ? (model.signIn?.message ?? "Saving your sign-in on the Core…") : "A few seconds",
                state: check(2, step)),
            trailing: EmptyView())
    }

    @ViewBuilder private func openAgain(_ page: URL?, show: Bool) -> some View {
        if let page, show {
            Button("Open Again") { model.opener(page) }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small)).help("Open the sign-in page again")
        }
    }

    /// The code the provider shows: pasted here, sent once through the Core, then cleared. Never sent for the person.
    private var codeField: some View {
        let s = model.signIn
        let empty = code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(alignment: .top, spacing: Space.s2) {
            CoreTextField(
                "", placeholder: "Paste the code", text: $code, error: s?.codeError ?? s?.inputError, mono: true,
                autofocus: true, onSubmit: sendCode
            )
            .accessibilityLabel("The code")
            .accessibilityIdentifier("sign-in-code")
            Button("Continue", action: sendCode)
                .buttonStyle(CoreButtonStyle(.prominent, size: .small, busy: s?.sending == true))
                .disabled(empty).padding(.top, Space.s1)
        }
        .padding(.top, Space.s1)
    }

    private func sendCode() {
        let c = code
        guard !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            let sent: Bool
            if flow.style(model) == .paste {
                await model.sendSignInCode(c)
                sent = model.signIn?.codeError == nil
            } else {
                sent = await model.sendGuidedInput(c)
            }
            if sent { code = "" }
        }
    }

    /// "Show details": the runner's own lines, for when something looks stuck. Closed by default.
    private func detailsDisclosure(_ s: SignInFlow?, _ step: SignInStep) -> some View {
        let lines = (s?.screen.isEmpty == false) ? s?.screen ?? [] : fallbackLines(step)
        return VStack(alignment: .leading, spacing: Space.s2) {
            Button {
                details.toggle()
            } label: {
                HStack(spacing: Space.s1) {
                    Image(systemName: "chevron.right").coreFont(size: MacTextSize.meta - 2, weight: .semibold)
                        .rotationEffect(.degrees(details ? 90 : 0))
                    Text(details ? "Hide details" : "Show details")
                }
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sign-in-details")
            if details {
                ScrollView {
                    Text(lines.joined(separator: "\n"))
                        .coreFont(size: MacTextSize.meta, design: .monospaced).foregroundStyle(GlassInk.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: Space.s8 * 4)
                .padding(Space.s3)
                .background(GlassInk.well, in: coreShape(Radius.control))
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fallbackLines(_ step: SignInStep) -> [String] {
        let all = ["Starting the sign-in on your Core…", "Opening the sign-in page…", "Waiting for the code…", "Saving…"]
        return Array(all.prefix(min(at(step) + 2, all.count)))
    }

    // MARK: 3. done

    var doneStep: some View {
        let plan = chosen.map(ProviderCatalog.kind) == .subscription
        let line =
            plan
            ? "Your plan’s models. New AI sessions can use it now."
            : flow.modelsFound.map { "\($0) models. New AI sessions can use it now." }
                ?? "New AI sessions can use it now."
        return VStack(spacing: Space.s3) {
            ConnArrival(kind: logo).padding(.bottom, Space.s2)
            Text("\(name) is ready").coreFont(size: MacTextSize.large, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            Text(line).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            CoreDialogFooter(
                cancel: CoreAction("Add Another") {
                    code = ""
                    copied = false
                    flow.again(model)
                },
                primary: CoreAction("Done", key: .primary, run: close)
            )
            .padding(.top, Space.s2)
        }
        .accessibilityIdentifier("account-add-done")
    }
}
