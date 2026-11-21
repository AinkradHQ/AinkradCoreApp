import CoreKit
import CoreUI
import Foundation

enum AdvancedTab: String, CaseIterable, Sendable {
    case limits, models
    var title: String {
        switch self {
        case .limits: "Limits"
        case .models: "Models and prices"
        }
    }
}

/// One row of the AI order list, worked out once so the view only draws.
struct OrderRow: Identifiable, Equatable {
    var id: Int64 { account.id }
    let account: AccountItem
    let number: Int
    let title: String
    let kind: ProviderKind
    let chip: OrderChip
    let sentence: String
    /// 0...1; nil while signing in (an indeterminate bar).
    let meter: Double?
    let model: String?
}

/// What an agent follows: the AI order, or an order of its own that starts with one account or holds only that one.
enum AgentChoice: Hashable, Sendable {
    case follow
    case first(Int64)
    case only(Int64)
    case custom
}

extension AccountsModel {
    // MARK: reading

    /// Reads the order when the Core serves API minor 95. Below that `aiOrderOn` is false and the old pages show.
    func reloadAIOrder(_ service: any AccountsService) async {
        guard await service.aiOrderSupported() else {
            aiOrderOn = false
            aiOrder = nil
            orderIDs = []
            return
        }
        aiOrderOn = true
        // A device that may not read it still sees its accounts, in the Core's list order.
        if let doc = try? await service.aiOrder() { aiOrder = doc }
        orderIDs = Self.merge(order: aiOrder?.items.map(\.account) ?? [], accounts: accounts.map(\.id))
    }

    /// The order's accounts that exist, then the accounts the order does not hold yet.
    nonisolated static func merge(order: [Int64], accounts: [Int64]) -> [Int64] {
        let have = Set(accounts)
        var seen = Set<Int64>()
        let listed = order.filter { have.contains($0) && seen.insert($0).inserted }
        return listed + accounts.filter { !seen.contains($0) }
    }

    // MARK: rows

    var orderRows: [OrderRow] {
        let accs = orderIDs.compactMap { account($0) }
        let verdicts = accs.map {
            (
                AccountVerdict.of($0, limits: limits(of: $0), budgets: budgets, inPool: true), $0.state,
                $0.meter?.limitHit ?? false
            )
        }
        let chips = OrderChips.chips(verdicts)
        return accs.enumerated().map { i, a in
            let facts = usageFacts(a, chip: chips[i])
            let kind =
                provider(a.provider).map(ProviderCatalog.kind)
                ?? (a.provider.hasSuffix("-sub") ? .subscription : .apiKey)
            return OrderRow(
                account: a, number: i + 1, title: title(a), kind: kind,
                chip: chips[i], sentence: UsageSentence.of(facts),
                meter: chips[i] == .signingIn ? nil : UsageSentence.meter(facts),
                model: aiOrder?.items.first { $0.account == a.id }?.model)
        }
    }

    func usageFacts(_ a: AccountItem, chip: OrderChip) -> UsageFacts {
        var f = UsageFacts(signing: chip == .signingIn, limitHit: chip == .limitHit)
        f.monthSpendMicros = a.monthSpendUSDMicros
        f.monthLimitMicros = a.monthLimitUSDMicros
        f.resetsAt = a.stateUntil
        if let m = a.meter {
            // The Core's own meter says it all: the sentence, the bar, the chip and when it is back.
            f.limitHit = f.limitHit || m.limitHit
            f.resetsAt = m.stateUntil ?? m.resetsAt ?? f.resetsAt
            f.share = m.fraction
            f.windowSecs = m.windowSecs ?? (m.window == nil ? nil : -1)
            (f.used, f.limit, f.unit) = (m.used, m.limit, m.unit)
            return f
        }
        let w = a.health?.windows ?? []
        if let p = w.first(where: { $0.name == "seven_day" }) {
            (f.share, f.windowSecs, f.resetsAt) = (p.utilization, 604_800, f.resetsAt ?? p.resetsAt)
        } else if let p = w.first(where: { $0.name == "five_hour" }) {
            (f.share, f.windowSecs, f.resetsAt) = (p.utilization, 18_000, f.resetsAt ?? p.resetsAt)
        } else if let l = limits(of: a).max(by: { $0.share < $1.share }) {
            (f.share, f.windowSecs) = (l.share, l.windowSecs)
        }
        return f
    }

    // MARK: models

    /// Reads the models of `a` with their prices and switches (0.10); empty below that.
    func reloadModels(_ a: AccountItem) async {
        guard let service, aiOrderOn else { return }
        modelRows[a.id] = await service.accountModels(account: a.id)
    }

    /// Switches a model on or off for an account. The switch moves at once and goes back when the Core refuses.
    func setModelAllowed(_ a: AccountItem, _ model: String, _ allowed: Bool) async {
        let before = modelRows[a.id]
        modelRows[a.id] = before?.map { r in
            var r = r
            if r.model == model { r.allowed = allowed }
            return r
        }
        let ok = await write(
            "model-\(a.id)-\(model)",
            reason: allowed
                ? "Allow \(model) on \(title(a))." : "Switch \(model) off for \(title(a)). Nothing will run it there.",
            done: allowed ? "\(model) allowed" : "\(model) switched off", keepsEdit: true
        ) { try await $0.setModelAllowed(account: a.id, model: model, allowed: allowed) }
        if !ok { modelRows[a.id] = before }
        await reloadModels(a)
    }

    // MARK: moves

    /// The `Item`s the Core takes for a whole list; the model each account runs is kept.
    func putItems(_ ids: [Int64]) -> [AIOrderPut.Item] {
        ids.prefix(AIOrderPut.maxItems).map { id in
            AIOrderPut.Item(account: id, model: aiOrder?.items.first { $0.account == id }?.model)
        }
    }

    /// Shows `ids` at once, writes them, and puts the old order back when the Core refuses or the person does not elevate.
    func reorder(
        _ ids: [Int64], reason: String = "Change the AI order. The first account that is ready serves new sessions."
    ) async {
        guard ids != orderIDs else { return }
        let before = orderIDs
        orderIDs = ids
        let items = putItems(ids)
        let ok = await write(
            "order", reason: reason, done: "Order saved", keepsEdit: true,
            undo: { [weak self] in await self?.reorder(before, reason: "Put the AI order back as it was.") }
        ) { _ = try await $0.setAIOrder(agent: nil, items: items) }
        if !ok {
            orderIDs = before
            if let why = writeError["order"] { host.shell.showToast(why, kind: .error) }
        }
    }

    func moveUp(_ id: Int64) async { await reorder(OrderMoves.up(orderIDs, id)) }
    func moveDown(_ id: Int64) async { await reorder(OrderMoves.down(orderIDs, id)) }
    func move(_ id: Int64, to index: Int) async {
        guard let from = orderIDs.firstIndex(of: id) else { return }
        await reorder(OrderMoves.moved(orderIDs, from: from, to: index))
    }

    /// "Check it now": a plan's sign-in, or a key's test.
    func checkNow(_ a: AccountItem) async {
        if a.isPlan { await checkPlan(a) } else { await test(a) }
    }

    // MARK: per-agent order

    var orderAgents: [String] {
        let own = (aiOrder?.overrides ?? []).map(\.agent)
        return Array(NSOrderedSet(array: own + knownAgents)) as? [String] ?? own
    }

    func agentChoice(_ agent: String) -> AgentChoice {
        guard let o = aiOrder?.overrides.first(where: { $0.agent == agent }) else { return .follow }
        return Self.choice(override: o.items.map(\.account), all: orderIDs)
    }

    nonisolated static func choice(override ids: [Int64], all: [Int64]) -> AgentChoice {
        guard let first = ids.first else { return .follow }
        if ids.count == 1 { return .only(first) }
        return ids == [first] + all.filter { $0 != first } ? .first(first) : .custom
    }

    nonisolated static func agentItems(_ c: AgentChoice, all: [Int64]) -> [Int64]? {
        switch c {
        case .follow, .custom: nil
        case .first(let x): [x] + all.filter { $0 != x }
        case .only(let x): [x]
        }
    }

    func setAgentOrder(_ agent: String, _ choice: AgentChoice) async {
        guard choice != .custom, choice != agentChoice(agent) else { return }
        let has = aiOrder?.overrides.contains { $0.agent == agent } ?? false
        let ids = Self.agentItems(choice, all: orderIDs)
        let items = ids.map(putItems)
        let was = agentChoice(agent)
        await write(
            "agent-\(agent)",
            reason: ids == nil ? "Make \(agent) follow the AI order." : "Give \(agent) an AI order of its own.",
            done: ids == nil ? "\(agent) follows the AI order" : "\(agent) has its own order", keepsEdit: true,
            undo: { [weak self] in await self?.setAgentOrder(agent, was) }
        ) {
            if let items {
                _ = try await $0.setAIOrder(agent: agent, items: items)
            } else if has {
                try await $0.clearAIOrder(agent: agent)
            }
        }
    }

    /// The words of one choice in the Per-agent select.
    func agentChoiceTitle(_ c: AgentChoice) -> String {
        func name(_ id: Int64) -> String {
            account(id).map(title) ?? "Account \(id)"
        }
        switch c {
        case .follow: return "Follow the AI order"
        case .first(let id): return "\(name(id)) first"
        case .only(let id): return "\(name(id)) only"
        case .custom: return "Its own order"
        }
    }
}
