import Foundation
import Testing

@testable import CoreKit
@testable import Pairing

private final class FakeControl: MacRunnerControl, @unchecked Sendable {
    let lock = NSLock()
    var bundled = true
    var enrolled: MacEnrolment?
    var registered: Bool?  // nil: not registered, else the `terminals` of the plist
    var status = RunnerRegistration.enabled
    var paired: [String] = []
    var pairError: MacRunnerFailure?
    var forgot = 0
    var isBundled: Bool { bundled }
    func registration(terminals: Bool) -> RunnerRegistration { registered == nil ? .notRegistered : status }
    func register(terminals: Bool) throws { registered = terminals }
    func unregister() throws { registered = nil }
    func enrolment() -> MacEnrolment? { enrolled }
    func pair(core: URL, token: String) async throws {
        if let pairError { throw pairError }
        paired.append(token)
        enrolled = MacEnrolment(deviceID: "d_mac", url: core.absoluteString)
    }
    func forgetEnrolment() {
        forgot += 1
        enrolled = nil
    }
    func openLoginItems() {}
}

@MainActor
private final class Recorder {
    var invites: [String] = []
    var revoked: [String] = []
    var declined = false
    var revokeFailure: String?
}

@MainActor
struct MacRunnerTests {
    private func make(
        _ c: FakeControl = FakeControl(), _ r: Recorder = Recorder()
    ) -> (MacRunnerModel, FakeControl, Recorder, UserDefaults) {
        let defaults = UserDefaults(suiteName: "macrunner-\(UUID().uuidString)")!
        let deps = MacRunnerDeps(
            coreURL: { URL(string: "https://core.example:7700") },
            makeInvite: { name in
                if r.declined { throw StepUpDeclined() }
                r.invites.append(name)
                return RunnerInvite(
                    pairingID: "p_1", name: name, token: "core.example:7700/FP.SECRET",
                    expiresAt: Date().addingTimeInterval(900))
            },
            revoke: { id in
                r.revoked.append(id)
                return r.revokeFailure
            })
        return (MacRunnerModel(control: c, deps: deps, defaults: defaults, macName: "Ahmed's Mac"), c, r, defaults)
    }

    @Test func itIsOnByDefaultWithTerminalsAndSaysTheWarning() {
        let (m, _, _, _) = make()
        #expect(m.useThisMac && m.terminals && m.isAvailable)
        #expect(MacRunnerModel.terminalsWarning == "Devices allowed to open terminals can reach this Mac's files.")
    }

    @Test func turningItOnMakesAnInvitePairsWithItAndStartsTheAgentWithTerminals() async {
        let (m, c, r, _) = make()
        await m.reconcile()
        #expect(r.invites == ["Ahmed's Mac"])
        #expect(c.paired == ["core.example:7700/FP.SECRET"])
        #expect(c.registered == true)
        #expect(m.state == .running && m.deviceID == "d_mac" && m.runnerID == "d_mac")
    }

    @Test func aMacAlreadyPairedAndRunningIsNotPairedAgain() async {
        let c = FakeControl()
        c.enrolled = MacEnrolment(deviceID: "d_old", url: "https://core.example:7700")
        c.registered = true
        let (m, _, r, _) = make(c)
        await m.reconcile()
        #expect(r.invites.isEmpty && c.paired.isEmpty && m.state == .running && m.deviceID == "d_old")
    }

    @Test func aPairingWithAnotherCoreIsReplaced() async {
        let c = FakeControl()
        c.enrolled = MacEnrolment(deviceID: "d_old", url: "https://other.example")
        let (m, _, r, _) = make(c)
        await m.reconcile()
        #expect(c.forgot == 1 && r.invites.count == 1 && m.deviceID == "d_mac")
    }

    @Test func aDeclinedTouchIDStartsNothing() async {
        let (m, c, r, _) = make()
        r.declined = true
        await m.reconcile()
        #expect(c.registered == nil && c.paired.isEmpty)
        guard case .failed(let why) = m.state else {
            Issue.record("expected failed, got \(m.state)")
            return
        }
        #expect(why.contains("Touch ID"))
    }

    @Test func aFailedPairingShowsTheReasonAndStartsNothing() async {
        let c = FakeControl()
        c.pairError = MacRunnerFailure(message: "The runner could not pair: invite expired")
        let (m, _, _, _) = make(c)
        await m.reconcile()
        #expect(m.state == .failed("The runner could not pair: invite expired") && c.registered == nil)
    }

    @Test func offStopsTheAgentRevokesTheDeviceAndForgetsTheKey() async {
        let (m, c, r, d) = make()
        await m.reconcile()
        await m.setUseThisMac(false)
        #expect(c.registered == nil && r.revoked == ["d_mac"] && c.enrolled == nil)
        #expect(m.state == .off && m.runnerID == nil && d.bool(forKey: MacRunnerModel.useKey) == false)
    }

    @Test func aRefusedRevokeIsSaidAndTheAgentStaysStopped() async {
        let (m, c, r, _) = make()
        await m.reconcile()
        r.revokeFailure = "Touch ID did not go through."
        await m.setUseThisMac(false)
        #expect(c.registered == nil)
        guard case .failed(let why) = m.state else {
            Issue.record("expected failed, got \(m.state)")
            return
        }
        #expect(why.contains("Revoke it in Devices"))
    }

    @Test func theTerminalsSwitchRestartsTheAgentWithTheOtherPlist() async {
        let (m, c, _, _) = make()
        await m.reconcile()
        await m.setTerminals(false)
        #expect(c.registered == false && !m.terminals)
        await m.setTerminals(true)
        #expect(c.registered == true)
    }

    @Test func theTerminalsSwitchDoesNothingWhileTheRunnerIsOff() async {
        let (m, c, _, _) = make()
        await m.setUseThisMac(false)
        await m.setTerminals(false)
        #expect(c.registered == nil)
    }

    @Test func offAtLaunchStopsALeftoverAgentWithoutRevoking() async {
        let c = FakeControl()
        c.registered = true
        let (m, _, r, d) = make(c)
        d.set(false, forKey: MacRunnerModel.useKey)
        await m.reconcile()
        #expect(c.registered == nil && r.revoked.isEmpty)
    }

    @Test func aBuildWithoutTheRunnerDoesNothing() async {
        let c = FakeControl()
        c.bundled = false
        let (m, _, r, _) = make(c)
        await m.reconcile()
        #expect(m.state == .unavailable && !m.isAvailable && r.invites.isEmpty && c.registered == nil)
    }

    @Test func aPendingApprovalIsSaid() async {
        let c = FakeControl()
        c.status = .needsApproval
        let (m, _, _, _) = make(c)
        await m.reconcile()
        #expect(m.state == .needsApproval)
    }

    @Test func forgettingTheCoreRemovesTheRunner() async {
        let (m, c, _, _) = make()
        await m.reconcile()
        await m.coreForgotten()
        #expect(c.registered == nil && c.enrolled == nil)
    }

    @Test func theRunnersEnrolmentFileIsRead() {
        let json = #"{"url":"https://core.example","device_id":"d_9","core_fp":"x","rotation_seq":0,"next_fp":null}"#
        #expect(
            LiveMacRunnerControl.parseEnrolment(Data(json.utf8))
                == MacEnrolment(deviceID: "d_9", url: "https://core.example"))
        #expect(LiveMacRunnerControl.parseEnrolment(Data("{}".utf8)) == nil)
    }

    @Test func aPairFailureShowsTheLastLine() {
        #expect(
            LiveMacRunnerControl.pairMessage("warn\nainkrad-runner: invite expired\n")
                == "The runner could not pair: ainkrad-runner: invite expired")
        #expect(LiveMacRunnerControl.pairMessage("") == "The runner could not pair with the Core.")
    }
}

@MainActor
struct MacRunnerSetupTests {
    private let fp = Wire.b64(Data(repeating: 7, count: 32))
    private let secret = Wire.b64(Data(repeating: 9, count: 16))

    private func finish(_ m: SetupWizardModel) async {
        m.linkText = "ainkrad://connect?host=core.example.com&fp=\(fp)&secret=\(secret)"
        m.connect()
        for _ in 0..<200 where m.stage == .connecting { try? await Task.sleep(for: .milliseconds(5)) }
    }

    private func paired() -> FakeDriver {
        let d = FakeDriver()
        d.approvals = [.success(.paired)]
        return d
    }

    private func runner(bundled: Bool) -> MacRunnerModel {
        let c = FakeControl()
        c.bundled = bundled
        let deps = MacRunnerDeps(
            coreURL: { nil }, makeInvite: { _ in throw StepUpDeclined() }, revoke: { _ in nil })
        return MacRunnerModel(
            control: c, deps: deps, defaults: UserDefaults(suiteName: "macrunner-\(UUID().uuidString)")!)
    }

    @Test func theEndScreenComesBeforeTheDesktopWhenTheRunnerIsInside() async {
        var opened = 0
        let m = SetupWizardModel(driver: paired(), macRunner: runner(bundled: true)) { opened += 1 }
        await finish(m)
        #expect(m.stage == .ready && opened == 0)
        m.finishSetup()
        #expect(opened == 1)
    }

    @Test func thereIsNoEndScreenWithoutARunnerInside() async {
        var opened = 0
        let m = SetupWizardModel(driver: paired(), macRunner: runner(bundled: false)) { opened += 1 }
        await finish(m)
        #expect(opened == 1)
    }

    @Test func theEndScreenSwitchOnlyRemembersTheChoice() {
        let r = runner(bundled: true)
        r.setPreference(false)
        #expect(!r.useThisMac && r.state == .off)
    }
}

/// The LaunchAgent plists bundled in the app: a Mac runner gets account sessions only with both agents on and the egress filter.
@MainActor
struct MacRunnerPlistTests {
    private func plist(_ name: String) throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        url.append(path: "App/Mac/LaunchAgents/\(name).plist")
        let obj = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try #require(obj as? [String: Any])
    }

    @Test func bothAgentsOfferAccountSessionsWithTheEgressFilter() throws {
        let plain = try plist("com.ainkrad.core.runner")
        let terms = try plist("com.ainkrad.core.runner.terminals")
        let a = try #require(plain["ProgramArguments"] as? [String])
        let b = try #require(terms["ProgramArguments"] as? [String])
        #expect(a.contains("--enable-agents") && !a.contains("--enable-pty"))
        #expect(b.contains("--enable-agents") && b.contains("--enable-pty"))
        let ea = try #require(plain["EnvironmentVariables"] as? [String: String])
        let eb = try #require(terms["EnvironmentVariables"] as? [String: String])
        #expect(ea["AINKRAD_AGENT_NETWORK"] == "filtered")
        #expect(ea["AINKRAD_AGENT_EGRESS_HOSTS"]?.split(separator: ",").contains("api.anthropic.com") == true)
        #expect(ea == eb)
    }

    @Test func theAccountsLineSaysWhatTheRunnerReports() {
        #expect(MacRunnerModel.accountsLine("Yes") == "Can use your accounts: Yes")
        #expect(
            MacRunnerModel.accountsLine("No (it cannot limit where AI sessions connect)").hasPrefix(
                "Can use your accounts: No ("))
        #expect(MacRunnerModel.accountsLine(nil) == "Can use your accounts: not reported yet")
    }
}
