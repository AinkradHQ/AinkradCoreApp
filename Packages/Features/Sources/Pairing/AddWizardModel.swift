import CoreKit
import Foundation
import Observation

/// Add a device or a runner, one guided flow (N17). It owns the choices and drives the two ways the Core can pair:
/// an invite QR (a device: nothing to compare afterwards) and the typed code (a runner, and a device when the Core cannot
/// make invites), where the approver still compares the check code. It reuses `InviteDeviceModel` and `AddDeviceModel`.
@MainActor @Observable
final class AddWizardModel {
    private(set) var kind: AddKind?
    var step = AddStep.what
    var name = ""
    var preset = AccessPreset.work
    var scopes = Set(AccessPreset.work.scopes)
    var terminals = true
    var agents = true
    private(set) var invite: InviteDeviceModel?
    private(set) var typed: AddDeviceModel?
    private(set) var runnerInvite: RunnerInviteModel?
    /// Under Advanced: the typed code, for a Linux server that the invite cannot serve.
    private(set) var typedInstead = false
    /// The device that answered, by the Core's list: its name and id.
    private(set) var connected: DeviceInfo?
    private(set) var testLine: String?
    private(set) var testing = false
    private(set) var held: [String] = []
    private weak var app: AppModel?

    init(app: AppModel, kind: AddKind? = nil) {
        self.app = app
        if let kind { choose(kind) }
    }

    var steps: [AddStep] { kind.map(AddWizardPlan.steps) ?? [.what] }
    var usesInvite: Bool { kind?.isRunner == false && app?.invites.isAvailable == true }
    /// A Linux server connects with a one-time runner invite: one command, 15 minutes, no check code.
    var usesRunnerInvite: Bool { kind == .linuxRunner && app?.invites.isAvailable == true && !typedInstead }
    /// The scopes the new device will get: what was chosen, cut to what this Mac holds.
    var granted: [String] {
        AddWizardPlan.narrowed(ScopeText.all.filter(scopes.contains), mine: held).granted
    }
    var dropped: [String] { AddWizardPlan.narrowed(ScopeText.all.filter(scopes.contains), mine: held).dropped }
    var onlyOneAdmin: Bool { app?.devices?.onlyAdmin != nil }
    var coreURL: String { app?.coreURL ?? "https://<your-core>" }
    var ended: Bool {
        if usesRunnerInvite { return runnerInvite.map { $0.phase == .expired || $0.phase == .withdrawn } ?? false }
        if usesInvite { return invite?.ended == true }
        if case .ended = typed?.stage { return true }
        return false
    }

    func choose(_ k: AddKind) {
        kind = k
        if name.isEmpty || AddKind.allCases.map(\.defaultName).contains(name) { name = k.defaultName }
        preset = AccessPreset.standard(for: k)
        scopes = Set(preset.scopes)
    }

    func pick(_ p: AccessPreset) {
        preset = p
        if p != .custom { scopes = Set(p.scopes) }
    }

    func setScope(_ s: String, _ on: Bool) {
        if on { scopes.insert(s) } else { scopes.remove(s) }
        preset = AccessPreset.matching(scopes)
    }

    var canGoNext: Bool {
        switch step {
        case .what: kind != nil
        case .install: kind != .phone
        case .access: !granted.isEmpty && !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .connect: connectedYet
        case .settings, .done: true
        }
    }

    var connectedYet: Bool {
        if usesRunnerInvite { return runnerInvite?.done == true }
        if usesInvite { return invite?.used == true }
        switch typed?.stage {
        case .approved?: return true
        default: return false
        }
    }

    func next() async {
        guard let kind, canGoNext, let n = AddWizardPlan.next(after: step, kind) else { return }
        step = n
        if n == .connect { await startConnect() }
        if n == .settings || n == .done { await findConnected() }
    }

    func back() {
        guard let kind, let p = AddWizardPlan.previous(before: step, kind) else { return }
        step = p
    }

    // MARK: connect

    /// Makes the invite or the code, behind Touch ID. Asks again only when the earlier one is gone.
    func startConnect() async {
        guard let app, let kind else { return }
        let label = name.trimmingCharacters(in: .whitespaces)
        if usesRunnerInvite {
            guard runnerInvite == nil || ended else { return }
            let m = runnerInvite ?? RunnerInviteModel(deps: runnerDeps(app))
            runnerInvite = m
            await m.create(name: label)
        } else if usesInvite {
            guard invite == nil || ended else { return }
            let m = InviteDeviceModel(host: app)
            await m.prepare()
            held = m.mine
            m.name = label
            m.scopes = Set(granted)
            invite = m
            await m.create()
        } else {
            let m = AddDeviceModel(host: app)
            m.name = label
            m.kind = kind.coreKind
            if !kind.isRunner { m.scopes = Set(granted) }
            typed = m
            app.watch(typed: m)
            await m.prepare()
            held = m.mine
            if !kind.isRunner { m.scopes = Set(granted) }
            await m.create()
        }
    }

    private func runnerDeps(_ app: AppModel) -> RunnerInviteDeps {
        RunnerInviteDeps(
            create: { name in
                try await app.elevated("Make a runner invite for \(name).", done: "made") {
                    try await app.invites.createRunnerInvite(name: name)
                }
            },
            status: { try await app.invites.status($0) },
            withdraw: { id in
                try await app.elevated("Withdraw the runner invite.", done: "withdrawn") {
                    try await app.invites.withdraw(id)
                }
            },
            runnerNames: { await app.terminals?.freshRunnerNames() ?? [] })
    }

    /// Advanced: give up the invite and use the typed code instead.
    func useTypedCode() async {
        guard usesRunnerInvite else { return }
        if let m = runnerInvite, !(await m.requestClose()) { return }
        runnerInvite = nil
        typedInstead = true
        await startConnect()
    }

    /// The poll while the connect screen is open.
    func poll() async {
        if usesRunnerInvite {
            await runnerInvite?.poll()
        } else if usesInvite {
            await invite?.refresh()
        } else {
            await typed?.refresh()
        }
        if connectedYet { await findConnected() }
    }

    func again() async {
        if usesRunnerInvite {
            await runnerInvite?.again(name: name.trimmingCharacters(in: .whitespaces))
            return
        }
        invite = nil
        typed?.restart()
        typed = nil
        await startConnect()
    }

    /// The device the Core now lists under that name: the newest one.
    func findConnected() async {
        guard connected == nil, let list = try? await app?.service?.devices() else { return }
        let label = name.trimmingCharacters(in: .whitespaces)
        connected = list.filter { $0.name == label && !$0.revoked }.max { $0.createdAt < $1.createdAt }
    }

    /// The runner's no-op test: a small job whose answer time is shown.
    func test() async {
        guard let id = connected?.id, let app else { return }
        testing = true
        testLine = await app.testRunner(id)
        testing = false
    }

    // MARK: closing

    /// True when nothing is left live: the dialog may close. A live QR is withdrawn first (see `InviteDeviceModel`).
    func requestClose() async -> Bool {
        if let runnerInvite { return await runnerInvite.requestClose() }
        if let invite { return await invite.requestClose() }
        if case .code = typed?.stage { await typed?.reject() }
        return true
    }

    func dialogDidClose() {
        runnerInvite?.takeBackCopy()
        invite?.dialogDidClose()
        app?.unwatch(typed: typed)
    }
}
