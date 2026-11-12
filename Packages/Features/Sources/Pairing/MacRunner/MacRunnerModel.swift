import CoreKit
import Foundation
import Observation

/// What the Mac runner needs from the app that owns the Core connection.
struct MacRunnerDeps: Sendable {
    var coreURL: @MainActor @Sendable () -> URL?
    /// A one-time runner invite (admin, Touch ID). Throws `StepUpDeclined` when the person did not unlock.
    var makeInvite: @MainActor @Sendable (_ name: String) async throws -> RunnerInvite
    /// Revokes the runner device; nil when it worked, else the reason in words.
    var revoke: @MainActor @Sendable (_ deviceID: String) async -> String?
}

/// "Use this Mac as a runner" (N16): the runner inside the app, paired by the app itself with no code, started by the system at
/// login, and removed (agent unregistered, device revoked) when the switch goes off. On by default (D1); terminals are on too (D2).
@MainActor @Observable
final class MacRunnerModel {
    enum State: Equatable {
        /// This build has no runner inside.
        case unavailable
        case off
        case working(String)
        /// Registered and started by the system.
        case running
        case needsApproval
        case failed(String)
    }

    static let useKey = "core.macRunner.on"
    static let terminalsKey = "core.macRunner.terminals"
    /// D2, shown beside the terminals switch.
    static let terminalsWarning = "Devices allowed to open terminals can reach this Mac's files."
    /// D3, until the Core can give a macOS runner its accounts.
    static let agentsNote = "AI sessions on this Mac start when the Core supports accounts on macOS."

    private(set) var state: State
    private(set) var deviceID: String?
    private let control: any MacRunnerControl
    private let defaults: UserDefaults
    private let deps: MacRunnerDeps
    private let macName: String
    private var busy = false

    init(control: any MacRunnerControl, deps: MacRunnerDeps, defaults: UserDefaults = .standard, macName: String? = nil)
    {
        self.control = control
        self.deps = deps
        self.defaults = defaults
        self.macName = macName ?? Host.current().localizedName ?? "This Mac"
        state = control.isBundled ? .off : .unavailable
        deviceID = control.enrolment()?.deviceID
    }

    var isAvailable: Bool { control.isBundled }
    /// On unless the person turned it off.
    var useThisMac: Bool { defaults.object(forKey: Self.useKey) as? Bool ?? true }
    var terminals: Bool { defaults.object(forKey: Self.terminalsKey) as? Bool ?? true }
    /// The runner list's "This Mac" badge.
    var runnerID: String? { useThisMac ? deviceID : nil }
    var isBusy: Bool { if case .working = state { true } else { false } }

    /// The Mac's own runner name in the Core.
    var runnerName: String { macName }

    // MARK: the switches

    func setUseThisMac(_ on: Bool) async {
        defaults.set(on, forKey: Self.useKey)
        if on { await start() } else { await stop(revoke: true) }
    }

    /// Only remembers the choice (setup's end screen, before the Core is connected); `reconcile` acts on it.
    func setPreference(_ on: Bool) { defaults.set(on, forKey: Self.useKey) }

    func setTerminals(_ on: Bool) async {
        defaults.set(on, forKey: Self.terminalsKey)
        guard useThisMac, control.isBundled, control.registration(terminals: on) != .notRegistered else { return }
        await start()
    }

    /// After the Core connects: bring the runner to what the switch says (setup, or a later launch).
    func reconcile() async {
        guard control.isBundled else { return }
        if useThisMac, let e = control.enrolment(), control.registration(terminals: terminals) == .enabled,
            let core = deps.coreURL(), Self.sameCore(e.url, core)
        {
            deviceID = e.deviceID
            state = .running
        } else if useThisMac {
            await start()
        } else if control.registration(terminals: terminals) != .notRegistered {
            await stop(revoke: false)
        }
    }

    /// The Core was forgotten: its runner pairing means nothing now.
    func coreForgotten() async {
        guard control.isBundled else { return }
        await stop(revoke: false)
    }

    // MARK: work

    private func start() async {
        guard control.isBundled, !busy, let core = deps.coreURL() else { return }
        busy = true
        defer { busy = false }
        do {
            if let e = control.enrolment(), !Self.sameCore(e.url, core) {
                control.forgetEnrolment()
                deviceID = nil
            }
            if control.enrolment() == nil {
                state = .working("Adding this Mac to the Core")
                let invite = try await deps.makeInvite(macName)
                try await control.pair(core: core, token: invite.token)
            }
            deviceID = control.enrolment()?.deviceID
            state = .working("Starting the runner")
            try control.register(terminals: terminals)
            state = control.registration(terminals: terminals) == .needsApproval ? .needsApproval : .running
        } catch is StepUpDeclined {
            state = .failed(
                "Touch ID was not completed, so this Mac was not added. Turn the switch off and on to try again.")
        } catch {
            state = .failed(CoreError.unwrapping(error)?.localizedDescription ?? error.localizedDescription)
        }
    }

    private func stop(revoke: Bool) async {
        busy = true
        defer { busy = false }
        state = .working("Removing this Mac as a runner")
        var note: String?
        do { try control.unregister() } catch {
            note = "macOS would not stop the runner: \(error.localizedDescription)"
        }
        if revoke, let id = control.enrolment()?.deviceID, let why = await deps.revoke(id) {
            note = "The runner stopped, but the Core still lists it. Revoke it in Devices. \(why)"
        }
        if note == nil || revoke { control.forgetEnrolment() }
        deviceID = control.enrolment()?.deviceID
        state = note.map(State.failed) ?? .off
    }

    /// The enrolment is for this Core when the hosts match (the port and scheme may be written differently).
    static func sameCore(_ a: String, _ b: URL) -> Bool {
        URL(string: a)?.host()?.lowercased() == b.host()?.lowercased()
    }

    func openLoginItems() { control.openLoginItems() }
}
