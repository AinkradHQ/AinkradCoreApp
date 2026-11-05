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
            return (m.needLook + m.accounts.filter { $0.phase != .disabled }.prefix(6))
                .filter { seen.insert($0.id).inserted }.map { "a-\($0.id)" }
        case .accounts where m.detail == nil:
            return m.providersByUse.flatMap { $0.1 }.map { "a-\($0.id)" }
        case .pools: return m.selectedPool.map { $0.members.map { "m-\($0)" } } ?? []
        case .bindings: return m.bindings.map { "b-\($0.id)" }
        default: return []
        }
    }

    static func move(_ m: AccountsModel, _ step: Int, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        let list = items(m)
        guard !list.isEmpty else { return .ignored }
        let i = list.firstIndex { $0 == m.cursor } ?? (step > 0 ? -1 : list.count)
        let next = list[min(max(i + step, 0), list.count - 1)]
        withAnimation(.spring(duration: 0.25)) { m.cursor = next }
        withAnimation(.spring(duration: 0.3)) { proxy.scrollTo(next, anchor: .center) }
        return .handled
    }

    /// ← → switch pools on Pools, and move like ↑ ↓ everywhere else.
    static func side(_ m: AccountsModel, _ step: Int, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        guard m.page == .pools, !m.pools.isEmpty else { return move(m, step, proxy) }
        let i = m.pools.firstIndex { $0.id == m.selectedPool?.id } ?? 0
        withAnimation(.spring(duration: 0.3)) {
            m.poolSelection = m.pools[min(max(i + step, 0), m.pools.count - 1)].id
            m.cursor = nil
        }
        return .handled
    }

    static func open(_ m: AccountsModel) -> KeyPress.Result {
        guard let c = m.cursor, let id = Int64(c.dropFirst(2)) else {
            return .ignored
        }
        if c.hasPrefix("a-") || c.hasPrefix("m-") {
            withAnimation(.spring(duration: 0.35)) {
                m.page = .accounts
                m.detail = id
                m.cursor = nil
            }
        }
        return .handled
    }

    static func back(_ m: AccountsModel) -> KeyPress.Result {
        guard m.detail != nil else { return .ignored }
        withAnimation(.spring(duration: 0.35)) {
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
            case "⌫": AccountDialogs.openDelete(m, a)
            default: return .ignored
            }
            return .handled
        }
        if m.page == .accounts, key == "f" {
            let all = AccountFilter.allCases
            withAnimation(.spring(duration: 0.3)) {
                m.filter = all[((all.firstIndex(of: m.filter) ?? 0) + 1) % all.count]
            }
            return .handled
        }
        if m.page == .pools, let p = m.selectedPool, !ro {
            switch key {
            case "d" where !p.isDefault: Task { await m.makeDefault(p) }
            case "a": AccountDialogs.openAddMember(m, pool: p)
            case "b": AccountDialogs.openBind(m, pool: p)
            case "⌫", "x":
                guard let c = m.cursor, c.hasPrefix("m-"), let id = Int64(c.dropFirst(2)), let a = m.account(id)
                else { return .ignored }
                Task { await m.remove(a, from: p) }
            default: return .ignored
            }
            return .handled
        }
        if m.page == .bindings, !ro, key == "u" || key == "⌫",
            let c = m.cursor, let b = m.bindings.first(where: { "b-\($0.id)" == c })
        {
            Task { await m.unbind(b) }
            return .handled
        }
        return .ignored
    }

    /// The keys this page answers, for the foot of the app.
    static func hint(_ m: AccountsModel) -> String {
        switch m.page {
        case .overview: "⌘1–5 pages · ↑↓ move · ↩ open · ⌘N connect"
        case .accounts where m.detail != nil: "esc back · T turn on/off · K new key · L limit · ⌫ remove"
        case .accounts: "↑↓ move · ↩ open · F filter · ⌘N connect"
        case .pools: "← → pool · ↑↓ account · D default · A add · B bind · ⌫ remove"
        case .bindings: "↑↓ move · U unbind · ⌘N bind"
        default: "⌘1–5 pages · ⌘J audit"
        }
    }
}
