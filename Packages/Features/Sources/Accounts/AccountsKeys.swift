import CoreUI
import SwiftUI

/// The Core app's keyboard, page by page. One cursor tile per page (`AccountsModel.cursor`): arrows move it and scroll to
/// it, Return opens it, Esc goes back, and letters act on it.
@MainActor
enum AccountsKeys {
    /// The cursor keys on the page now, in reading order.
    static func items(_ m: AccountsModel) -> [String] {
        switch m.page {
        case .overview:
            var seen = Set<Int64>()
            let cards = (m.needLook + m.accounts.filter { $0.phase != .disabled }.prefix(6))
                .filter { seen.insert($0.id).inserted }.map { "a-\($0.id)" }
            let first = m.providers.filter { m.defaultPool($0.id).flatMap { m.firstReady(in: $0) } != nil }
            return cards + first.map { "t-\($0.id)" }
        case .accounts where m.detail == nil:
            return m.providersByUse.flatMap { $0.1 }.map { "a-\($0.id)" }
        case .pools: return m.selectedPool.map { $0.members.map { "m-\($0)" } } ?? []
        case .budgets:
            let mine = m.budgets.filter { ["account", "pool"].contains($0.kind) }
            return (mine + m.budgets.filter { !["account", "pool"].contains($0.kind) }).map { "g-\($0.id)" }
        case .prices:
            return m.prices.sorted { ($0.provider, $0.model) < ($1.provider, $1.model) }.map { "p-\($0.id)" }
        default: return []
        }
    }

    static func move(_ m: AccountsModel, _ step: Int, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        let list = items(m)
        guard !list.isEmpty else { return .ignored }
        let i = list.firstIndex { $0 == m.cursor } ?? (step > 0 ? -1 : list.count)
        let next = list[min(max(i + step, 0), list.count - 1)]
        withAnimation(Motion.out(Motion.ui)) { m.cursor = next }
        withAnimation(Motion.out(Motion.ui)) { proxy.scrollTo(next, anchor: .center) }
        return .handled
    }

    /// ← → switch pools on Pools, and move like ↑ ↓ everywhere else.
    static func side(_ m: AccountsModel, _ step: Int, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        guard m.page == .pools, !m.pools.isEmpty else { return move(m, step, proxy) }
        let i = m.pools.firstIndex { $0.id == m.selectedPool?.id } ?? 0
        withAnimation(Motion.out(Motion.ui)) {
            m.poolSelection = m.pools[min(max(i + step, 0), m.pools.count - 1)].id
            m.cursor = nil
        }
        return .handled
    }

    static func open(_ m: AccountsModel) -> KeyPress.Result {
        if let c = m.cursor, c.hasPrefix("t-"),
            let a = m.defaultPool(String(c.dropFirst(2))).flatMap({ m.firstReady(in: $0) })
        {
            withAnimation(Motion.out(Motion.move)) {
                m.page = .accounts
                m.detail = a.id
                m.cursor = nil
            }
            return .handled
        }
        if let c = m.cursor, c.hasPrefix("p-"), !m.readOnly,
            let p = m.prices.first(where: { "p-\($0.id)" == c })
        {
            AccountDialogs.openPrice(m, editing: p)
            return .handled
        }
        guard let c = m.cursor, let id = Int64(c.dropFirst(2)) else {
            return .ignored
        }
        if c.hasPrefix("g-"), let b = m.budgets.first(where: { $0.id == id }), !m.readOnly {
            AccountDialogs.openBudget(m, editing: b)
            return .handled
        }
        if c.hasPrefix("a-") || c.hasPrefix("m-") {
            withAnimation(Motion.out(Motion.move)) {
                m.page = .accounts
                m.detail = id
                m.cursor = nil
            }
        }
        return .handled
    }

    static func back(_ m: AccountsModel) -> KeyPress.Result {
        guard m.detail != nil else { return .ignored }
        withAnimation(Motion.out(Motion.move)) {
            m.cursor = m.detail.map { "a-\($0)" }
            m.detail = nil
        }
        return .handled
    }

    static func letter(_ m: AccountsModel, _ key: String) -> KeyPress.Result {
        let ro = m.readOnly
        if m.page == .accounts, let id = m.detail, let a = m.account(id), !ro {
            switch key {
            case "t": Task { await m.setEnabled(a, a.phase == .disabled) }
            case "k": AccountDialogs.openConnect(m, provider: a.provider, replacing: a)
            case "l": AccountDialogs.openCap(m, a)
            case "s": AccountDialogs.openLimits(m, a)
            case "v": Task { await m.test(a) }
            case "⌫": AccountDialogs.openDelete(m, a)
            case "p" where m.pools(of: a).isEmpty:
                if let p = m.defaultPool(a.provider) ?? m.pools(for: a.provider).first {
                    AccountDialogs.openAddMember(m, pool: p)
                } else {
                    AccountDialogs.openNewPool(m)
                }
            default: return .ignored
            }
            return .handled
        }
        if m.page == .budgets, !ro, let c = m.cursor, c.hasPrefix("g-"),
            let b = m.budgets.first(where: { "g-\($0.id)" == c })
        {
            switch key {
            case "e": AccountDialogs.openBudget(m, editing: b)
            case "r" where b.standing == .stopped || b.standing == .over: AccountDialogs.openRaise(m, b)
            case "⌫", "x": AccountDialogs.openDeleteBudget(m, b)
            default: return .ignored
            }
            return .handled
        }
        if m.page == .accounts, key == "f" {
            let all = AccountFilter.allCases
            withAnimation(Motion.out(Motion.ui)) {
                m.filter = all[((all.firstIndex(of: m.filter) ?? 0) + 1) % all.count]
            }
            return .handled
        }
        if m.page == .pools, let p = m.selectedPool, !ro {
            switch key {
            case "d" where !p.isDefault: Task { await m.makeDefault(p) }
            case "a": AccountDialogs.openAddMember(m, pool: p)
            case "⌫", "x":
                guard let c = m.cursor, c.hasPrefix("m-"), let id = Int64(c.dropFirst(2)), let a = m.account(id)
                else { return .ignored }
                Task { await m.remove(a, from: p) }
            default: return .ignored
            }
            return .handled
        }
        return .ignored
    }

    /// The keys this page answers, for the foot of the app.
    static func hint(_ m: AccountsModel) -> String {
        switch m.page {
        case .overview: "⌘1–4 pages · ↑↓ move · ↩ open · ⌘N connect"
        case .accounts where m.detail != nil:
            "esc back · V test · T turn on/off · P add to a pool · K new key · L at once · S per session · ⌫ remove"
        case .accounts: "↑↓ move · ↩ open · F filter · ⌘N connect"
        case .pools: "← → pool · ↑↓ account · D default · A add · ⌫ remove"
        case .budgets: "↑↓ move · E edit · R raise · ⌫ remove · ⌘N new budget"
        case .prices: "↑↓ move · ↩ change · ⌘N new price"
        default: "⌘1–4 pages · ⌘J audit"
        }
    }
}
