import Testing

@testable import Shell

struct ConnectionChipTests {
    private func of(_ l: CoreLink, up: Bool = true, n: Int = 0) -> ConnectionChipState? {
        ConnectionChipState.of(link: l, networkUp: up, attempt: n)
    }

    @Test func fourStates() {
        #expect(of(.live) == .online)
        #expect(of(.reconnecting, n: 3) == .reconnecting(attempt: 3))
        #expect(of(.connecting) == .reconnecting(attempt: 0))
        #expect(of(.offline, up: false) == .noNetwork)
        #expect(of(.reconnecting, up: false) == .noNetwork)
        #expect(of(.offline) == .coreNotAnswering)
    }

    @Test func noCoreNoChip() { #expect(of(.none) == nil) }

    @Test func networkOnlyMattersWhenTheLinkIsDown() { #expect(of(.live, up: false) == .online) }

    @Test func words() {
        #expect(ConnectionChipState.online.title(core: "core.ainkrad.io") == "core.ainkrad.io")
        #expect(ConnectionChipState.reconnecting(attempt: 3).title(core: "x") == "Reconnecting… (try 3)")
        #expect(ConnectionChipState.noNetwork.title(core: "x") == "No network")
        #expect(ConnectionChipState.coreNotAnswering.title(core: "x") == "Core not answering · Retry")
    }
}
