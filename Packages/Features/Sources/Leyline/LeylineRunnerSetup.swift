import Foundation
import Observation

/// A host Leyline knows, as Add runner offers it ("a server I can SSH into"). Public so the Add runner flow, which lives beside
/// the pairing code, can list and set up hosts without reaching into Leyline's own types.
public struct RunnerHostChoice: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// "ubuntu@10.0.0.4" or the OS when Leyline learned it.
    public let detail: String
    /// This host already was made a runner: it is listed but not offered again.
    public let isRunner: Bool
}

/// "Make Runner" on one host, as the Add runner flow follows it: Touch ID, the invite copied over SSH, the installer typed into a
/// terminal the person watches (the sudo password is theirs), then the runner pairing. One per host; reads the live host page state.
/// What the Runner card on a host page shows of its runner.
public struct RunnerGlance: Equatable, Sendable {
    public let online: Bool
    /// The AI tool being installed now ("OpenCode") and how far it is, 0 to 100.
    public let installing: String?
    public let percent: Int
    public init(online: Bool, installing: String?, percent: Int) {
        self.online = online
        self.installing = installing
        self.percent = percent
    }
}

@MainActor @Observable
public final class RunnerSetup {
    public enum Phase: Equatable {
        case idle, starting
        /// The installer runs in the terminal; the invite ends at the date.
        case waiting(until: Date?)
        case paired(device: String)
        case expired
    }

    private let state: HostPageState
    init(state: HostPageState) { self.state = state }

    public var hostName: String { state.host?.name ?? "the host" }
    public var phase: Phase {
        switch state.runnerState {
        case .idle: .idle
        case .starting: .starting
        case .waiting(let until): .waiting(until: until)
        case .paired(let d): .paired(device: d)
        case .expired: .expired
        }
    }

    public func start() async { await state.makeRunner() }
}

extension LeylineModel {
    /// The hosts that can become runners, in the order Leyline lists them.
    public var runnerChoices: [RunnerHostChoice] {
        hosts.map {
            RunnerHostChoice(
                id: $0.id, name: $0.name, detail: [$0.os, $0.login].compactMap { $0 }.joined(separator: " · "),
                isRunner: $0.runnerDevice != nil)
        }
    }

    public func runnerSetup(hostID: String) -> RunnerSetup {
        RunnerSetup(state: HostPageState(model: self, hostID: hostID))
    }

    /// Opens Leyline's Add Host sheet, for "Add a host" inside Add runner.
    public func presentAddHost() { HostDialogs.openAdd(self, login: "") }
}
