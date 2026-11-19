import Foundation
import Leyline
import Observation
import Terminals

/// Add a runner (mockup 13): four places a runner can be, a short "what may it do", a live connect screen with plain failure
/// reasons, and a done screen. It drives the models that already do the work: the Mac runner switch, Leyline's Make Runner, a
/// runner invite for the one-line command, and a device invite for another Mac.
@MainActor @Observable
final class AddRunnerModel {
    enum Path: CaseIterable, Equatable { case thisMac, anotherMac, ssh, command }
    enum Step: Int, Equatable { case pick, allow, connect, failed, done }

    /// One line of the connect screen.
    struct Check: Identifiable, Equatable {
        enum State { case done, current, pending, bad }
        let id: Int
        let title: String
        let working: String
        let note: String
        var state: State
        /// 0...1 while this line is the one being worked on and the work says how far it is.
        var progress: Double?
    }

    private(set) var path: Path?
    var step = Step.pick
    var terminals = true
    var agents = true
    /// SSH: the host chosen on the connect screen, and the setup running on it.
    var hostID: String?
    private(set) var setup: RunnerSetup?
    /// The command and another-Mac paths ride on the Add wizard's models.
    private(set) var wizard: AddWizardModel?
    private(set) var failure: (title: String, text: String)?
    private(set) var connectedName: String?
    private(set) var connectedID: String?
    private(set) var progress: RunnerProgress?
    private var applied = false
    private weak var app: AppModel?

    init(app: AppModel) { self.app = app }

    var coreURL: String { app?.coreURL ?? "https://<your-core>" }
    var hosts: [RunnerHostChoice] { app?.leyline.runnerChoices ?? [] }
    var picking: Bool { path == .ssh && setup == nil && step == .connect }
    var macRunner: MacRunnerModel? { app?.macRunner }

    // MARK: moving

    func choose(_ p: Path) {
        path = p
        step = .allow
    }

    func back() {
        switch step {
        case .allow: step = .pick
        case .connect, .failed:
            setup = nil
            failure = nil
            step = .allow
        default: break
        }
    }

    func next() async {
        guard let path, step == .allow else { return }
        failure = nil
        step = .connect
        switch path {
        case .thisMac: await startThisMac()
        case .ssh: break  // the host is picked on the connect screen
        case .command: await startInvite(kind: .linuxRunner)
        case .anotherMac: await startInvite(kind: .mac)
        }
    }

    func again() async {
        failure = nil
        setup = nil
        wizard = nil
        step = .allow
        await next()
    }

    func startOver() async {
        _ = await requestClose()
        path = nil
        step = .pick
        connectedName = nil
        connectedID = nil
        progress = nil
        applied = false
        hostID = nil
        failure = nil
    }

    // MARK: the four paths

    private func startThisMac() async {
        guard let m = app?.macRunner else { return }
        await m.setTerminals(terminals)
        await m.setUseThisMac(true)
        if case .failed(let why) = m.state { fail("This Mac could not start the runner", why) }
    }

    func startSSH() async {
        guard let id = hostID, let app else { return }
        let s = app.leyline.runnerSetup(hostID: id)
        setup = s
        await s.start()
    }

    func addHost() { app?.leyline.presentAddHost() }

    private func startInvite(kind: AddKind) async {
        guard let app else { return }
        let w = AddWizardModel(app: app, kind: kind)
        w.name = kind == .mac ? "Mac" : "Runner"
        w.terminals = terminals
        w.agents = agents
        wizard = w
        await w.startConnect()
    }

    // MARK: waiting

    /// One look while the connect screen is open (every two seconds from the view).
    func poll() async {
        guard step == .connect, let app else { return }
        await app.terminals?.refreshRunnerProgress()
        switch path {
        case .thisMac: pollThisMac()
        case .ssh: pollSSH()
        case .command, .anotherMac: await pollInvite()
        case nil: break
        }
        if connectedName != nil { await finishIfConnected() }
    }

    private func pollThisMac() {
        guard let m = app?.macRunner else { return }
        switch m.state {
        case .failed(let why): fail("This Mac could not start the runner", why)
        case .needsApproval:
            fail(
                "macOS needs your OK",
                "Allow Ainkrad Core in System Settings > General > Login Items. The runner starts as soon as you do.")
        default:
            progress = app?.terminals?.runnerProgress(id: m.deviceID)
            if let p = progress, p.online { connectedName = p.name; connectedID = p.id }
        }
    }

    private func pollSSH() {
        guard let s = setup else { return }
        switch s.phase {
        case .paired:
            connectedName = s.hostName
            progress = app?.terminals?.runnerProgress(name: s.hostName)
            connectedID = progress?.id
        case .expired:
            fail(
                "The invite ended",
                "Nothing was installed and the invite is gone. Start again when you are at the terminal.")
        default: break
        }
    }

    private func pollInvite() async {
        guard let w = wizard else { return }
        await w.poll()
        if w.connectedYet {
            var named: String?
            if case .connected(let n)? = w.runnerInvite?.phase { named = n }
            connectedName = named ?? w.connected?.name ?? w.name
            progress = app?.terminals?.runnerProgress(name: connectedName)
            connectedID = progress?.id ?? w.connected?.id
        } else if w.ended {
            fail("The invite ran out", "It works for 15 minutes, once. Make a new one and try again.")
        } else if w.makeFailed {
            fail("The invite was not made", "Touch ID was not completed or the Core could not be reached. Try again.")
        }
    }

    /// Once connected: apply the choices from the Allow step, then show Done.
    private func finishIfConnected() async {
        // The runner can be paired before the Core's list shows it: wait for its id.
        guard let id = connectedID, let app, !applied else { return }
        applied = true
        if let s = app.terminals?.runnerSettings(named: connectedName ?? ""), s.editable,
            s.terminals != terminals || s.agents != agents
        {
            await app.terminals?.changeRunner(id, terminals: terminals, agents: agents)
        }
        step = .done
    }

    private func fail(_ title: String, _ text: String) {
        failure = (title, text)
        step = .failed
    }

    // MARK: lines of the connect screen

    func checks() -> [Check] {
        switch path {
        case .thisMac: thisMacChecks()
        case .ssh: sshChecks()
        default: []
        }
    }

    private func line(_ i: Int, _ title: String, _ working: String, _ note: String, at current: Int, bad: Bool = false, progress: Double? = nil) -> Check {
        let state: Check.State = bad && i == current ? .bad : i < current ? .done : i == current ? .current : .pending
        return Check(id: i, title: title, working: working, note: note, state: state, progress: state == .current ? progress : nil)
    }

    private func thisMacChecks() -> [Check] {
        let running = macRunner?.state == .running
        let connected = connectedName != nil
        let current = !running ? 0 : !connected ? 1 : 3
        let installing = progress?.installing
        return [
            line(0, "Runner is on", "Starting the runner…", "Inside its own home folder", at: current),
            line(
                1, "AI tools are set up", installing.map { "Installing \($0)…" } ?? "Checking the AI tools…",
                "Ainkrad installs them in tested versions", at: current,
                progress: installing == nil ? nil : Double(progress?.percent ?? 0) / 100),
            line(2, "Connected to Core", "Connecting to Core…", "Waiting for the first hello", at: current),
        ]
    }

    private func sshChecks() -> [Check] {
        let phase = setup?.phase ?? .idle
        let current: Int
        switch phase {
        case .idle, .starting: current = 1
        case .waiting: current = 3
        case .paired: current = 5
        case .expired: current = 3
        }
        let name = setup?.hostName ?? "the host"
        return [
            line(0, "Reached \(name)", "Reaching \(name)…", "Over SSH, with the key you chose", at: current),
            line(1, "Signed in", "Signing in…", "Your key was accepted", at: current),
            line(2, "Put the invite there", "Putting the invite there…", "One time, 15 minutes", at: current),
            line(3, "Runner is installed", "Type your sudo password in the terminal…", "Ainkrad never sees it", at: current),
            line(4, "Connected to Core", "Connecting to Core…", "Waiting for the first hello", at: current),
        ]
    }

    // MARK: closing

    func requestClose() async -> Bool {
        if let wizard, !(await wizard.requestClose()) { return false }
        wizard?.dialogDidClose()
        return true
    }
}
