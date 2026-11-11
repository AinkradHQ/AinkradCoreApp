import Foundation
import Testing

@testable import Accounts

@MainActor
struct AccountsOrderTests {
    func make() async -> (AccountsModel, FakeService, FakeHost) {
        let host = FakeHost()
        let model = AccountsModel(host: host)
        let svc = FakeService()
        svc.gateState = GateState(mode: 1, providerAccounts: 1)
        svc.poolList = [pool(1, "anthropic", def: true, members: [1])]
        svc.accountList = [account(1, "tech")]
        svc.chainList = [
            ChainItem(
                id: 5, name: "default", isDefault: true,
                entries: [ChainEntryItem(pool: 1, provider: "anthropic", harness: "claude", model: nil)])
        ]
        model.use(svc)
        try? await Task.sleep(for: .milliseconds(80))
        return (model, svc, host)
    }

    @Test func dragInTheOrderListReplacesTheChainWithTheNewSequence() async {
        let (m, svc, _) = await make()
        svc.poolList.append(pool(2, "openai", provider: "openai", def: true, members: []))
        svc.chainList = [
            ChainItem(
                id: 5, name: "default", isDefault: true,
                entries: [
                    ChainEntryItem(pool: 1, provider: "anthropic", harness: "claude", model: nil),
                    ChainEntryItem(pool: 2, provider: "openai", harness: "codex", model: nil),
                ])
        ]
        await m.reload()
        #expect(m.orderSeats.count == 2)
        await m.moveSeat(from: 0, to: 1)
        #expect(svc.chainList.first?.entries.map(\.pool) == [2, 1])
        #expect(svc.log.contains("replaceChain 5 default 2"))
    }

    @Test func accountsListInTheOrderAgentsTryThem() async {
        let (m, svc, _) = await make()
        svc.accountList = [account(1, "tech"), account(2, "spare", provider: "openai"), account(3, "creative")]
        svc.poolList = [
            pool(1, "anthropic", def: true, members: [3]),
            pool(2, "openai", provider: "openai", def: true, members: [2]),
        ]
        svc.chainList = [
            ChainItem(
                id: 5, name: "default", isDefault: true,
                entries: [
                    ChainEntryItem(pool: 2, provider: "openai", harness: "codex", model: nil),
                    ChainEntryItem(pool: 1, provider: "anthropic", harness: "claude", model: nil),
                ])
        ]
        await m.reload()
        #expect(m.accountsInOrder.map(\.label) == ["spare", "creative", "tech"])
        #expect(m.seatIndex(of: m.account(3)!) == 1)
    }
}
