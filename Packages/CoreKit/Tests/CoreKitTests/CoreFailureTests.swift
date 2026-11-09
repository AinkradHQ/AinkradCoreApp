import AinkradClient
import Foundation
import OpenAPIRuntime
import Testing

@testable import CoreKit

/// The Core's refusals are typed outputs of the generated client; reading `.ok` on one throws an "unexpected response" error
/// that is not a `CoreError`. `CoreFailure.of` reads the Core's own answer back out, for every service family.
@Suite struct CoreFailureTests {
    private func body(_ code: String, _ message: String) -> Components.Schemas.ErrorBody {
        .init(code: code, errorId: "err_1", message: message)
    }

    private func refusal(_ read: () throws -> Void) -> CoreError? {
        do { try read() } catch { return CoreFailure.of(error) }
        Issue.record("did not throw")
        return nil
    }

    @Test func adminSettingConflict() {
        let out = Operations.SetSetting.Output.conflict(.init(body: .json(body("conflict", "changed meanwhile"))))
        #expect(refusal { _ = try out.ok } == .http(status: 409, code: "conflict", message: "changed meanwhile"))
    }

    @Test func terminalOpenConflictAndLimit() {
        let conflict = Operations.CreateTerminal.Output.conflict(.init(body: .json(body("no_runner", "m"))))
        #expect(refusal { _ = try conflict.created } == .http(status: 409, code: "no_runner", message: "m"))
        let limit = Operations.CreateTerminal.Output.conflict(.init(body: .json(body("terminal_limit", "too many"))))
        #expect(refusal { _ = try limit.created } == .http(status: 409, code: "terminal_limit", message: "too many"))
    }

    @Test func agentStartConflictAndLimit() {
        let c = Operations.CreateAgentSession.Output.conflict(.init(body: .json(body("conflict", "busy"))))
        #expect(refusal { _ = try c.ok } == .http(status: 409, code: "conflict", message: "busy"))
        let l = Operations.CreateAgentSession.Output.conflict(.init(body: .json(body("limit_reached", "cap"))))
        #expect(refusal { _ = try l.ok } == .http(status: 409, code: "limit_reached", message: "cap"))
        let b = Operations.CreateAgentSession.Output.badRequest(.init(body: .json(body("bad_request", "no prompt"))))
        #expect(refusal { _ = try b.ok } == .http(status: 400, code: "bad_request", message: "no prompt"))
    }

    @Test func pairingApproveAndLookups() {
        let a = Operations.ApprovePairing.Output.notFound(.init(body: .json(body("not_found", "no such pairing"))))
        #expect(refusal { _ = try a.ok } == .http(status: 404, code: "not_found", message: "no such pairing"))
        let c = Operations.ApprovePairing.Output.conflict(.init(body: .json(body("sas_mismatch", "m"))))
        #expect(refusal { _ = try c.ok } == .http(status: 409, code: "sas_mismatch", message: "m"))
        let h = Operations.ListRunners.Output.internalServerError(.init(body: .json(body("internal", "boom"))))
        #expect(refusal { _ = try h.ok } == .http(status: 500, code: "internal", message: "boom"))
    }

    /// 401/403/429 are thrown by the signing middleware as `CoreError` inside the client's wrapper: they must pass through
    /// untouched, so the Touch ID prompt and the "this Mac can only look" paths keep firing.
    @Test func stepUpAndScopeRefusalsPassThrough() {
        for core in [CoreError.stepUpRequired, .forbiddenScope, .rateLimited(retryAfter: 3)] {
            let wrapped = ClientError(
                operationID: "x", operationInput: 0, causeDescription: "middleware", underlyingError: core)
            #expect(CoreFailure.of(wrapped) == core)
            #expect(CoreFailure.of(core) == core)
        }
    }

    @Test func somethingElseIsNotACoreAnswer() {
        #expect(CoreFailure.of(CancellationError()) == nil)
    }
}
