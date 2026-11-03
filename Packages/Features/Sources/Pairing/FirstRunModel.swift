import CoreKit
import Foundation
import Observation

/// CoreKit's `DevicePairing`, as the first-run screen uses it, so tests can stand in for it.
protocol PairingDriver: Sendable {
    func claim(_ credential: PairingCredential, endpoint: URL?) async throws -> PairingClaim
    func resume() async throws -> PairingClaim?
    func confirmSAS() async throws
    func awaitApproval() async throws -> PairingOutcome
    func cancel() async throws -> PairingCancel
}

struct LivePairing: PairingDriver {
    let pairing: DevicePairing
    func claim(_ credential: PairingCredential, endpoint: URL?) async throws -> PairingClaim {
        try await pairing.claim(credential, endpoint: endpoint)
    }
    func resume() async throws -> PairingClaim? { try await pairing.resume() }
    func confirmSAS() async throws { try await pairing.confirmSAS() }
    func awaitApproval() async throws -> PairingOutcome { try await pairing.awaitApproval() }
    func cancel() async throws -> PairingCancel { try await pairing.cancel() }
}

/// Why first run (or a connection) stopped, in words a person can act on.
struct Failure: Equatable {
    enum Kind: Equatable {
        case offline(String)
        case rateLimited(Int?)
        case identityMismatch
        case unproven
        case clockSkew(Int64?)
        case rejected
        case expired
        case badCode
        case sasMismatch
        case oldApp
        case revokedHere
        case cancelledAfterApproval(String)
        case keychain(String)
        case other(String)
    }
    let kind: Kind
    /// Fatal: nothing here can be retried; the only way on is to start over.
    var fatal: Bool {
        switch kind {
        case .identityMismatch, .sasMismatch, .cancelledAfterApproval, .revokedHere: true
        default: false
        }
    }

    static func from(_ error: any Error) -> Failure {
        guard let e = CoreError.unwrapping(error) else { return Failure(kind: .other(error.localizedDescription)) }
        switch e {
        case .offline(let m): return Failure(kind: .offline(m))
        case .rateLimited(let s): return Failure(kind: .rateLimited(s.map { Int($0.rounded(.up)) }))
        case .coreIdentityMismatch: return Failure(kind: .identityMismatch)
        case .coreUnproven: return Failure(kind: .unproven)
        case .clockSkew(let t): return Failure(kind: .clockSkew(t))
        case .notApproved(let s): return Failure(kind: s == "rejected" ? .rejected : .expired)
        case .pairingExpired: return Failure(kind: .expired)
        case .pairingFailed: return Failure(kind: .badCode)
        case .sasMismatch: return Failure(kind: .sasMismatch)
        case .noSharedMinor: return Failure(kind: .oldApp)
        case .revoked: return Failure(kind: .revokedHere)
        case .keyStore(let m): return Failure(kind: .keychain(m))
        case .authFailed:
            return Failure(
                kind: .other(
                    "The Core did not accept this Mac. It may have been revoked, or locked out for a few minutes."))
        default: return Failure(kind: .other(e.localizedDescription))
        }
    }
}

/// What the screens show of a claim.
struct ClaimInfo: Equatable {
    let sas: String
    let deviceID: String
    let coreFingerprint: String
    init(sas: String, deviceID: String, coreFingerprint: String) {
        self.sas = sas
        self.deviceID = deviceID
        self.coreFingerprint = coreFingerprint
    }
    init(_ c: PairingClaim) { self.init(sas: c.sas, deviceID: c.deviceID, coreFingerprint: c.coreFingerprint) }
}

/// The first-run flow: address and code, claiming, the check code, waiting for the approver, done (or why not).
@MainActor @Observable
final class FirstRunModel {
    enum Stage: Equatable {
        case form, claiming, sas, approved
        case failed(Failure)
    }

    private(set) var stage: Stage = .form
    var endpointText = ""
    /// Always in the form `ABCDE-FGHJK`: set it through `typeCode`.
    private(set) var codeText = ""
    private(set) var endpointError: String?
    private(set) var codeError: String?
    private(set) var claim: ClaimInfo?
    /// The person said the check code matches the approver's.
    private(set) var matched = false
    /// The Core says the approver approved; the claim waits on the person's "matches".
    private(set) var approverApproved = false
    private(set) var retryAt: Date?
    private(set) var endpoint: URL?

    private let driver: any PairingDriver
    private let onPaired: @MainActor () -> Void
    /// Debug: where a live-test script reads the check code from.
    private let sasSink: (@MainActor (String) -> Void)?
    private var waiting: Task<Void, Never>?

    init(
        driver: any PairingDriver, sasSink: (@MainActor (String) -> Void)? = nil,
        onPaired: @escaping @MainActor () -> Void
    ) {
        self.driver = driver
        self.onPaired = onPaired
        self.sasSink = sasSink
    }

    func typeCode(_ typed: String) { codeText = CodeFormat.format(typed) }

    var usesQR: Bool { CodeFormat.isQR(codeText) }
    var canSubmit: Bool { CodeFormat.isComplete(codeText) && (usesQR || !endpointText.isEmpty) }

    func submit() async {
        endpointError = nil
        codeError = nil
        let credential: PairingCredential
        do { credential = try PairingCredential.parse(codeText) } catch {
            codeError = error.localizedDescription
            return
        }
        var url: URL?
        if case .code = credential {
            do { url = try EndpointInput.parse(endpointText) } catch {
                endpointError = error.localizedDescription
                return
            }
        }
        endpoint = url
        stage = .claiming
        do {
            claim = ClaimInfo(try await driver.claim(credential, endpoint: url))
            showClaim()
        } catch { fail(error) }
    }

    /// A pairing the app left waiting before it quit.
    func resume() async {
        do {
            guard let c = try await driver.resume() else { return }
            claim = ClaimInfo(c)
            showClaim()
        } catch { fail(error) }
    }

    func confirmMatch() async {
        guard stage == .sas, !matched else { return }
        do {
            try await driver.confirmSAS()
            matched = true
            if approverApproved { handle(try await driver.awaitApproval()) }
        } catch { fail(error) }
    }

    /// "It doesn't match" or Cancel: the pairing is given up and the Core told nothing it should keep.
    func cancel() async {
        waiting?.cancel()
        waiting = nil
        do {
            switch try await driver.cancel() {
            case .cleared: reset()
            case .revokeDeviceOnApprover(let id): stage = .failed(Failure(kind: .cancelledAfterApproval(id)))
            }
        } catch { fail(error) }
    }

    /// Back to the form. The address stays; the code is gone (it is single use).
    func reset() {
        waiting?.cancel()
        waiting = nil
        stage = .form
        codeText = ""
        claim = nil
        matched = false
        approverApproved = false
        retryAt = nil
        codeError = nil
        endpointError = nil
    }

    /// Back to the form with everything kept, for a failure that is about the address.
    func editAddress() {
        stage = .form
        retryAt = nil
    }

    func finish() { onPaired() }

    private func showClaim() {
        guard let claim else { return }
        stage = .sas
        sasSink?(claim.sas)
        waiting?.cancel()
        waiting = Task { [weak self] in
            guard let self else { return }
            do { handle(try await driver.awaitApproval()) } catch is CancellationError {} catch { fail(error) }
        }
    }

    private func handle(_ outcome: PairingOutcome) {
        switch outcome {
        case .paired: stage = .approved
        case .awaitingConfirmation: approverApproved = true
        }
    }

    private func fail(_ error: any Error) {
        let f = Failure.from(error)
        if case .rateLimited(let s) = f.kind { retryAt = Date().addingTimeInterval(TimeInterval(s ?? 30)) }
        waiting?.cancel()
        stage = .failed(f)
    }
}

#if DEBUG
extension FirstRunModel {
    /// Snapshot scenes: set the screen without a Core.
    func debugSet(
        _ stage: Stage, endpoint: String = "", code: String = "", claim: ClaimInfo? = nil, matched: Bool = false,
        approverApproved: Bool = false, retryAt: Date? = nil
    ) {
        endpointText = endpoint
        typeCode(code)
        self.claim = claim
        self.matched = matched
        self.approverApproved = approverApproved
        self.retryAt = retryAt
        self.stage = stage
    }
}
#endif
