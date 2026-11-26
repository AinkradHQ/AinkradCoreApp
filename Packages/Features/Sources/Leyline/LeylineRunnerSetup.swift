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

/// "Make Runner" on one host, as the Add runner flow follows it: Touch ID, the invite copied over SSH, the installer run by the
/// Core over SSH with nothing to type (the system service with passwordless sudo, else a runner for that user), then the pairing. One per host; reads the live host page state.
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
        case failed(String)
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
        case .failed(let why): .failed(why)
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
                isRunner: $0.runnerDevice != nil || runner(of: $0) != nil)
        }
    }

    public func runnerSetup(hostID: String) -> RunnerSetup {
        RunnerSetup(state: HostPageState(model: self, hostID: hostID))
    }

    /// Opens Leyline's Add Host sheet, for "Add a host" inside Add runner.
    public func presentAddHost() { HostDialogs.openAdd(self, login: "") }
}

/// A paired runner, as the host page asks "is this host one?": its device id, name and whether it is connected.
public struct RunnerSummary: Equatable, Sendable {
    public let id: String
    public let name: String
    public let online: Bool
    public init(id: String, name: String, online: Bool) {
        self.id = id
        self.name = name
        self.online = online
    }
}

extension LeylineModel {
    /// The runner this host is: its `runner_device` when the Core linked them, else a runner named like the host's address
    /// (its first label for a DNS name), else like the host. The Core reports no runner hostname or IP, and has no route to
    /// link a host to a runner made apart from it, so a name is all there is to match on.
    /// ponytail: name match only; match by address once the runner list carries one.
    nonisolated static func runner(of h: HostItem, in runners: [RunnerSummary]) -> RunnerSummary? {
        if let d = h.runnerDevice { return runners.first { $0.id == d } }
        func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let isIP = h.address.allSatisfy { $0.isNumber || $0 == "." || $0 == ":" }
        let label = isIP ? h.address : String(h.address.split(separator: ".").first ?? "")
        for want in [h.address, label, h.name].map(norm) where !want.isEmpty {
            if let r = runners.first(where: { norm($0.name) == want }) { return r }
        }
        return nil
    }

    func runner(of h: HostItem) -> RunnerSummary? { Self.runner(of: h, in: runners?() ?? []) }
}
