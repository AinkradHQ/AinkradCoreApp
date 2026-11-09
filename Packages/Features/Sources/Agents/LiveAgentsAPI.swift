import AinkradClient
import CoreKit
import CoreUI
import Foundation
import OpenAPIRuntime

/// The generated client's agent routes, mapped to this module's types. Errors come out as `CoreError`.
public struct LiveAgentsAPI: AgentsAPI {
    let connection: CoreConnection
    private var client: Client { connection.client }
    public init(connection: CoreConnection) { self.connection = connection }

    public func runners() async throws -> [RunnerInfo] {
        try await run {
            try await client.listRunners().ok.body.json.map { r in
                RunnerInfo(
                    id: r.id, name: r.name, online: r.online ?? false, degraded: r.degraded ?? false,
                    load: Int(r.load ?? 0), capacity: r.capacity.map(Int.init),
                    drivers: (r.drivers ?? []).compactMap(\.name))
            }
        }
    }

    public func chains() async throws -> [ChainOption] {
        do {
            return try await run {
                try await client.listChains().ok.body.json.map { c in
                    ChainOption(
                        id: c.id, name: c.name, isDefault: c.isDefault,
                        steps: c.entries.map { "\($0.harness) · \($0.model ?? "default model")" })
                }
            }
        } catch CoreError.forbiddenScope { return [] }
    }

    public func sessions(before: Int64?, limit: Int) async throws -> [AgentSessionInfo] {
        try await run {
            let q = Operations.ListAgentSessions.Input.Query(before: before, limit: Int32(limit))
            return try await client.listAgentSessions(query: q).ok.body.json.map(Self.session)
        }
    }

    public func session(_ id: String) async throws -> AgentSessionInfo {
        try await run {
            switch try await client.getAgentSession(path: .init(id: id)) {
            case .ok(let o): return Self.session(try o.body.json)
            case .notFound(let r): throw Self.fail(r)
            default: throw Self.unknown
            }
        }
    }

    public func transcript(_ id: String, after: Int64, limit: Int) async throws -> TranscriptPage {
        try await run {
            switch try await client.getAgentTranscript(
                path: .init(id: id), query: .init(after: after, limit: Int32(limit)))
            {
            case .ok(let o):
                let t = try o.body.json
                return TranscriptPage(entries: t.entries.map(Self.entry), lastSeq: t.lastSeq)
            case .notFound(let r): throw Self.fail(r)
            default: throw Self.unknown
            }
        }
    }

    public func create(_ new: NewAgentSession) async throws -> AgentSessionInfo {
        try await run {
            let policy = try OpenAPIObjectContainer(unvalidatedValue: ["mode": new.mode])
            // From a chain or an agent the account the Core picks sets the harness and model: sending either is a 400.
            let plain = new.chain == nil && new.agent == nil
            let body = Components.Schemas.NewAgentSession(
                agent: new.agent, chain: new.chain, harness: plain ? new.harness : nil, model: plain ? new.model : nil,
                policy: policy, prompt: new.prompt, runner: new.runner,
                secrets: new.secrets.isEmpty ? nil : new.secrets.map { .init(name: $0, _var: $0) })
            switch try await client.createAgentSession(body: .json(body)) {
            case .ok(let o): return Self.session(try o.body.json)
            case .badRequest(let r): throw Self.fail(r)
            case .notFound(let r): throw Self.fail(r)
            case .conflict(let r): throw Self.fail(r)
            case .undocumented(let status, let p): throw await Self.status(status, p)
            default: throw Self.unknown
            }
        }
    }

    public func send(_ id: String, text: String) async throws -> AgentSessionInfo {
        try await run {
            switch try await client.sendAgentMessage(path: .init(id: id), body: .json(.init(text: text))) {
            case .ok(let o): return Self.session(try o.body.json)
            case .badRequest(let r): throw Self.fail(r)
            case .notFound(let r): throw Self.fail(r)
            case .conflict(let r): throw Self.fail(r)
            case .undocumented(let status, let p): throw await Self.status(status, p)
            default: throw Self.unknown
            }
        }
    }

    public func cancel(_ id: String) async throws -> AgentSessionInfo {
        try await run {
            switch try await client.cancelAgentSession(path: .init(id: id)) {
            case .ok(let o): return Self.session(try o.body.json)
            case .notFound(let r): throw Self.fail(r)
            case .conflict(let r): throw Self.fail(r)
            case .undocumented(let status, let p): throw await Self.status(status, p)
            default: throw Self.unknown
            }
        }
    }

    public func kill(_ id: String) async throws -> AgentSessionInfo {
        try await run {
            switch try await client.killAgentSession(path: .init(id: id)) {
            case .ok(let o): return Self.session(try o.body.json)
            case .notFound(let r): throw Self.fail(r)
            case .conflict(let r): throw Self.fail(r)
            case .undocumented(let status, let p): throw await Self.status(status, p)
            default: throw Self.unknown
            }
        }
    }

    public func resume(_ id: String) async throws -> AgentSessionInfo {
        try await run {
            switch try await client.resumeAgentSession(path: .init(id: id)) {
            case .ok(let o): return Self.session(try o.body.json)
            case .notFound(let r): throw Self.fail(r)
            case .conflict(let r): throw Self.fail(r)
            case .undocumented(let status, let p): throw await Self.status(status, p)
            default: throw Self.unknown
            }
        }
    }

    public func wake(_ id: String, key: String) async throws {
        try await run {
            switch try await client.wakeAgentSession(path: .init(id: id), body: .json(.init(key: key))) {
            case .ok: return
            case .notFound(let r): throw Self.fail(r)
            case .conflict(let r): throw Self.fail(r)
            case .undocumented(let status, let p): throw await Self.status(status, p)
            default: throw Self.unknown
            }
        }
    }

    public func decide(_ id: String, request: String, approved: Bool) async throws -> AgentSessionInfo {
        try await run {
            switch try await client.decideAgentApproval(
                path: .init(id: id, request: request), body: .json(.init(approved: approved)))
            {
            case .ok(let o): return Self.session(try o.body.json)
            case .badRequest(let r): throw Self.fail(r)
            case .notFound(let r): throw Self.fail(r)
            case .conflict(let r): throw Self.fail(r)
            case .undocumented(let status, let p): throw await Self.status(status, p)
            default: throw Self.unknown
            }
        }
    }

    public func events() -> AsyncStream<AgentFeed> {
        let source = connection.events()
        return AsyncStream { out in
            let task = Task {
                for await update in source {
                    switch update {
                    case .live: out.yield(.live)
                    case .reconnecting: out.yield(.reconnecting)
                    case .gap: out.yield(.gap)
                    case .ended(let e): out.yield(.ended(e.localizedDescription))
                    case .event(let e):
                        guard e.kind.hasPrefix("agent.") else { continue }
                        let p = e.payload.value
                        out.yield(
                            .event(
                                AgentEvent(
                                    kind: e.kind, session: p["session"] as? String, request: p["request"] as? String,
                                    tool: p["tool"] as? String, from: (p["from"] as? NSNumber)?.int64Value,
                                    to: (p["to"] as? NSNumber)?.int64Value)))
                    }
                }
                out.finish()
            }
            out.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: mapping

    private static let unknown = CoreError.protocolViolation("The Core answered something this app does not know.")

    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch {
            throw CoreError.unwrapping(error) ?? error
        }
    }

    static func session(_ s: Components.Schemas.AgentSession) -> AgentSessionInfo {
        let outcome = s.outcome?.value
        let u = s.usage
        return AgentSessionInfo(
            id: s.id, runner: s.runner, harness: s.harness, model: s.model, state: SessionState(rawValue: s.state),
            outcome: (outcome?["kind"] as? String).map { SessionOutcome(rawValue: $0) },
            outcomeReason: outcome?["reason"] as? String, createdAt: s.createdAt, updatedAt: s.updatedAt,
            endedAt: s.endedAt, lastSeq: s.lastSeq,
            usage: u.map {
                AgentUsageInfo(
                    input: $0.input, output: $0.output, cacheRead: $0.cacheRead, cacheWrite: $0.cacheWrite,
                    costMicros: $0.costUsdMicros)
            }, resumes: s.resumes.map(Int.init), index: s.index)
    }

    static func entry(_ e: Components.Schemas.AgentTranscriptEntry) -> TranscriptEntry {
        let body = e.body.value.compactMapValues { $0 }
        return TranscriptEntry(
            seq: e.seq, at: Date(timeIntervalSince1970: TimeInterval(e.atMs) / 1000), kind: EntryParser.kind(body))
    }

    /// A status the contract does not list (502 `runner_failed`, 503 `runner_busy`): its error body, when it has one.
    private static func status(_ code: Int, _ payload: UndocumentedPayload) async -> CoreError {
        var code_ = "error"
        var message = "The Core could not do that (\(code))."
        if let body = payload.body, let data = try? await Data(collecting: body, upTo: 16 * 1024),
            let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            code_ = o["code"] as? String ?? code_
            message = o["message"] as? String ?? message
        }
        return .http(status: code, code: code_, message: message)
    }
    private static func fail(_ r: Components.Responses.Conflict) -> CoreError {
        let b = try? r.body.json
        return .http(status: 409, code: b?.code ?? "conflict", message: b?.message ?? "The Core refused that.")
    }
    private static func fail(_ r: Components.Responses.BadRequest) -> CoreError {
        .badRequest(message: (try? r.body.json)?.message ?? "The Core refused that.")
    }
    private static func fail(_ r: Components.Responses.NotFound) -> CoreError {
        .http(status: 404, code: "not_found", message: (try? r.body.json)?.message ?? "The Core does not know that.")
    }
}
