import AinkradClient
import CoreKit
import CoreUI
import SwiftUI

/// A session's spend as Core's ledger has it (the source of truth, not the harness's own meter), and, when it ran on one of
/// Core's accounts, that account: its key stays with the runner's gateway and never enters the sandbox.
public struct SessionLedger: Equatable, Sendable {
    public var costMicros: Int64
    public var tokens: Int64
    /// Some calls had no price: their tokens count, their cost doesn't.
    public var unpriced: Bool
    /// The Core account it used through the gateway, with that account's per-session limits.
    public var account: String?
    public var maxUSDMicros: Int64?
    public var maxTokens: Int64?
    public init(
        costMicros: Int64, tokens: Int64, unpriced: Bool, account: String? = nil, maxUSDMicros: Int64? = nil,
        maxTokens: Int64? = nil
    ) {
        self.costMicros = costMicros
        self.tokens = tokens
        self.unpriced = unpriced
        self.account = account
        self.maxUSDMicros = maxUSDMicros
        self.maxTokens = maxTokens
    }

    /// Spend against the account's per-session limit, 0...1, when it has one.
    var share: Double? {
        if let m = maxUSDMicros, m > 0 { return Double(costMicros) / Double(m) }
        if let t = maxTokens, t > 0 { return Double(tokens) / Double(t) }
        return nil
    }
}

extension LiveAgentsAPI {
    public func ledger(_ session: String) async throws -> SessionLedger? {
        let events: [Components.Schemas.CostEvent]
        do {
            events = try await connection.client.listCosts(query: .init(session: session, limit: 100)).ok.body.json
        } catch {
            // A device without `admin`, or a Core older than the ledger: nothing to show, not an error.
            if case .forbiddenScope? = CoreError.unwrapping(error) { return nil }
            throw CoreError.unwrapping(error) ?? error
        }
        var l = SessionLedger(
            costMicros: events.compactMap(\.costUsdMicros).reduce(0, +),
            tokens: events.reduce(0) { $0 + $1.inputTokens + $1.outputTokens + $1.cacheTokens },
            unpriced: events.contains { $0.basis == "unpriced" })
        if let id = events.compactMap(\.accountId).first,
            let a = try? await connection.client.getAccount(path: .init(id: String(id))).ok.body.json
        {
            l.account = a.label
            l.maxUSDMicros = a.sessionLimits?.maxUsdMicros
            l.maxTokens = a.sessionLimits?.maxTokens
        }
        return l
    }
}

extension AgentsModel {
    /// Reads the ledger for a session now, then every 15 s while it runs.
    func followLedger(_ id: String) async {
        while !Task.isCancelled {
            if let api, let l = try? await api.ledger(id) { ledgers[id] = l }
            guard sessions.session(id)?.live == true else { return }
            try? await Task.sleep(for: .seconds(15))
        }
    }
}

/// Under the session's chips: whose key it uses (held by the runner), and what the ledger says it spent, against the
/// account's per-session limit when there is one. A session stopped at its limit says so.
struct SessionSpendStrip: View {
    let session: AgentSessionInfo
    let ledger: SessionLedger

    var body: some View {
        let share = ledger.share
        let capped = session.outcome == .tokenCap || session.stoppedByBudget
        let hue = capped || (share ?? 0) >= 1 ? GlassInk.red : (share ?? 0) >= 0.8 ? GlassInk.orange : GlassInk.green
        HStack(spacing: Space.s3) {
            if let a = ledger.account {
                Label("\(a) · key held by the runner", systemImage: "lock.shield.fill")
                    .foregroundStyle(GlassInk.secondary)
                    .help("The key is used by the runner's gateway and never enters the agent's sandbox.")
            }
            Spacer(minLength: Space.s2)
            if capped {
                Label(
                    session.stoppedByBudget ? "Stopped: budget reached" : "Stopped at its limit",
                    systemImage: "gauge.with.dots.needle.100percent"
                )
                .font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(GlassInk.red)
            }
            Text(spentWords).font(.system(size: MacTextSize.body, weight: .semibold).monospacedDigit())
                .help(
                    ledger.unpriced
                        ? "Some calls had no price: their tokens count, their cost doesn't." : "From Core's ledger")
            if let share {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        coreShape(3).fill(GlassInk.track.opacity(0.6))
                        coreShape(3).fill(hue.gradient).frame(width: g.size.width * min(1, share))
                            .shadow(color: hue.opacity(0.5), radius: 4)
                    }
                }
                .frame(width: 140, height: 6)
                .animation(.smooth(duration: 0.6), value: share)
            }
        }
        .font(.system(size: MacTextSize.meta))
        .accessibilityElement(children: .combine)
    }

    private var spentWords: String {
        let spent = AgentWords.cost(ledger.costMicros) ?? "$0.00"
        let star = ledger.unpriced ? " + unpriced" : ""
        if let m = ledger.maxUSDMicros, m > 0 { return "\(spent)\(star) of \(AgentWords.cost(m) ?? "") this session" }
        if let t = ledger.maxTokens, t > 0 {
            return "\(AgentWords.tokens(ledger.tokens)) of \(AgentWords.tokens(t)) tokens · \(spent)\(star)"
        }
        return "\(spent)\(star) spent"
    }
}
