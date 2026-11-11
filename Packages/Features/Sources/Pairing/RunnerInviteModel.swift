import CoreKit
import Foundation
import Observation

/// A runner invite as the Core hands it out, once. The token is a secret: it is shown on screen and copied by the person,
/// never written to a log, so every description of it is redacted.
struct RunnerInvite: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let pairingID: String
    let name: String
    let token: String
    let expiresAt: Date
    var description: String { "RunnerInvite(\(pairingID), \(name))" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: ["pairingID": pairingID, "name": name]) }
}

/// What the runner invite flow needs from the app: each one does its own Touch ID, so tests bring their own.
struct RunnerInviteDeps: Sendable {
    var create: @MainActor @Sendable (_ name: String) async throws -> RunnerInvite
    /// The Core's status for the invite: `live` until a runner claims it, then `approved`.
    var status: @MainActor @Sendable (_ pairingID: String) async throws -> String
    var withdraw: @MainActor @Sendable (_ pairingID: String) async throws -> Void
    /// The names of the runners the Core lists now.
    var runnerNames: @MainActor @Sendable () async -> [String]
}

/// Add a Linux server as a runner (N17): make a one-time invite, show the one command with the token in it, count the 15
/// minutes down, and tell "Waiting for the runner…" from "Connected: <name>" by asking the Core. No check code.
@MainActor @Observable
final class RunnerInviteModel {
    enum Phase: Equatable {
        case idle, making, waiting
        case connected(String)
        case expired, withdrawn
    }

    private(set) var phase = Phase.idle
    private(set) var invite: RunnerInvite?
    private(set) var error: String?
    private(set) var copied = false
    private let deps: RunnerInviteDeps
    private let pasteboard: any LinkPasteboard
    private var before: Set<String> = []
    private var clearTask: Task<Void, Never>?
    private var copiedCount: Int?
    private var generation = 0

    init(deps: RunnerInviteDeps, pasteboard: any LinkPasteboard = SystemLinkPasteboard()) {
        self.deps = deps
        self.pasteboard = pasteboard
    }

    /// The command the person runs on the server.
    var command: String? { invite.map { AddWizardPlan.runnerInviteCommand(token: $0.token) } }
    var live: Bool { phase == .waiting }
    var done: Bool { if case .connected = phase { true } else { false } }

    /// Whole seconds left of the 15 minutes; 0 once over.
    func secondsLeft(now: Date) -> Int { max(0, Int((invite?.expiresAt.timeIntervalSince(now) ?? 0).rounded(.up))) }
    /// "14:59".
    static func clock(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }

    func create(name: String) async {
        guard phase != .making else { return }
        generation += 1
        let mine = generation
        error = nil
        phase = .making
        before = Set(await deps.runnerNames())
        do {
            let made = try await deps.create(name)
            guard mine == generation else {
                // Closed or restarted while it was being made: nobody will see it, so it goes at once.
                try? await deps.withdraw(made.pairingID)
                return
            }
            invite = made
            phase = .waiting
        } catch is StepUpDeclined {
            phase = .idle
        } catch {
            self.error = CoreError.unwrapping(error)?.localizedDescription ?? error.localizedDescription
            phase = .idle
        }
    }

    /// The clock moved: an invite past its 15 minutes is over, whatever the Core says next.
    func tick(now: Date) {
        guard phase == .waiting, secondsLeft(now: now) == 0 else { return }
        phase = .expired
        forget()
    }

    /// One look at the Core: the invite's status and the runner list.
    func poll() async {
        guard phase == .waiting, let id = invite?.pairingID, let name = invite?.name else { return }
        let status = try? await deps.status(id)
        let names = await deps.runnerNames()
        guard phase == .waiting, invite?.pairingID == id else { return }
        switch status {
        case "approved", "claimed":
            phase = .connected(names.first { !before.contains($0) } ?? name)
            forget()
        case "rejected", "expired", "burned":
            phase = status == "rejected" ? .withdrawn : .expired
            forget()
        default:
            if let new = names.first(where: { !before.contains($0) && $0 == name }) {
                phase = .connected(new)
                forget()
            }
        }
    }

    /// Takes the invite back (Touch ID is the dependency's business).
    func withdraw() async {
        guard phase == .waiting, let id = invite?.pairingID else { return }
        error = nil
        do {
            try await deps.withdraw(id)
            phase = .withdrawn
            forget()
        } catch is StepUpDeclined {
        } catch {
            if CoreError.unwrapping(error)?.inviteIsGone == true {
                phase = .withdrawn
                forget()
            } else {
                self.error = "The Core could not be reached, so this invite is still live. Try again."
            }
        }
    }

    /// The dialog is closing. True when nothing is left live.
    func requestClose() async -> Bool {
        generation += 1
        guard phase == .waiting else {
            forget()
            return true
        }
        await withdraw()
        return phase != .waiting
    }

    /// Start over after an expired or withdrawn invite.
    func again(name: String) async {
        invite = nil
        phase = .idle
        await create(name: name)
    }

    // MARK: the copied command

    func copy() {
        guard let command else { return }
        copiedCount = pasteboard.write(secret: command)
        copied = true
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            if !Task.isCancelled { self?.takeBackCopy() }
        }
    }

    /// Clears the pasteboard only if it still holds what this model put there.
    func takeBackCopy() {
        clearTask?.cancel()
        clearTask = nil
        copied = false
        guard let count = copiedCount else { return }
        copiedCount = nil
        if pasteboard.changeCount == count { pasteboard.clear() }
    }

    /// Once the invite is spent or over, the token is not kept anywhere.
    private func forget() {
        takeBackCopy()
        invite = invite.map { RunnerInvite(pairingID: $0.pairingID, name: $0.name, token: "", expiresAt: $0.expiresAt) }
    }
}
