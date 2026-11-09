import Foundation
import Testing

@testable import Accounts

@MainActor
struct ConnectionsTests {
    func make(empty: Bool = false) async -> (ConnectionsModel, SampleConnections, FakeHost) {
        let host = FakeHost()
        let m = ConnectionsModel(host: host)
        m.opener = { _ in }
        m.pollEvery = .milliseconds(1)
        let s = SampleConnections(empty: empty)
        m.use(s)
        await m.reload()
        return (m, s, host)
    }

    private func settle(_ m: ConnectionsModel, until done: (ConnFlow.Step?) -> Bool) async {
        for _ in 0..<500 where !done(m.flow?.step) { try? await Task.sleep(for: .milliseconds(2)) }
    }

    @Test func listsByKindAndSaysWhatEachMayDo() async {
        let (m, _, _) = await make()
        #expect(m.load == .ready)
        #expect(m.liveKinds.map(\.id) == ["github", "jira"])
        #expect(m.laterKinds.map(\.id) == ["linear", "slack"])
        #expect(m.items(of: "github").count == 2)
        #expect(m.needLook == 1)
        #expect(m.access(m.items[0]) == "Can read code and issues in all repositories.")
        m.filter = .needsLook
        #expect(m.items(of: "github").map(\.id) == [2])
    }

    @Test func gitHubSignInWalksItsStepsAndAddsTheConnection() async {
        let (m, _, _) = await make()
        await m.startFlow("github")
        #expect(m.flow?.userCode == "WDJB-MJHT")
        m.openSignIn()
        await settle(m) { if case .chooseResources = $0 { true } else { false } }
        guard case .chooseResources(let login, _)? = m.flow?.step else {
            Issue.record("no repo step")
            return
        }
        #expect(login == "@sample-dev")
        await m.choose(site: nil)
        #expect(m.flow?.isConnected == true)
        #expect(m.items(of: "github").count == 3)
        #expect(m.items.last?.isDefault == false)  // the kind already has a default
    }

    @Test func choosingRepositoriesOnGitHubFinishesByItself() async {
        let (m, _, _) = await make()
        var opened: [URL] = []
        m.opener = { opened.append($0) }
        await m.startFlow("github")
        m.openSignIn()
        await settle(m) { if case .chooseResources = $0 { true } else { false } }
        m.openInstall()
        #expect(m.installing)
        await settle(m) { if case .connected = $0 { true } else { false } }
        #expect(m.flow?.isConnected == true)
        #expect(opened.last?.absoluteString == "https://github.com/apps")
    }

    @Test func aFailedSignInSaysWhatToDoNotACode() async {
        let (m, s, _) = await make()
        s.failNext = true
        await m.startFlow("jira")
        m.openSignIn()
        await settle(m) { if case .failed = $0 { true } else { false } }
        guard case .failed(let title, let fix)? = m.flow?.step else {
            Issue.record("did not fail")
            return
        }
        #expect(title == "The browser didn't come back in time.")
        #expect(!fix.contains("_"))
        m.stopFlow()
    }

    @Test func changesGoThroughTouchIDAndADeclineChangesNothing() async {
        let (m, _, host) = await make()
        let c = m.items[0]
        #expect(await m.rename(c, to: "Mine"))
        #expect(m.item(c.id)?.name == "Mine")
        #expect(host.reasons.last == "Rename Personal GitHub to Mine.")
        host.declines = true
        #expect(await m.disconnect(m.item(c.id)!) == false)
        #expect(m.item(c.id) != nil)
        #expect(m.writeError.isEmpty)
    }

    @Test func accessAndDefaultAreSaved() async {
        let (m, _, _) = await make()
        let org = m.items[1]
        #expect(await m.setAccess(org, allowed: ["read", "write"], only: ["sample/core"]))
        #expect(m.access(m.item(org.id)!) == "Can read code and issues and create and change things in sample/core.")
        await m.makeDefault(org)
        #expect(m.items(of: "github").filter(\.isDefault).map(\.id) == [org.id])
    }

    @Test func aHealthEventSaysOnceWhenASignInStartsNeedingYou() async {
        let (m, s, host) = await make()
        var notes: [String] = []
        m.notify = { id, _, _ in notes.append(id) }
        m.event(kind: "connection.health")
        try? await Task.sleep(for: .milliseconds(50))
        #expect(host.shell.toast == nil)  // the expired one was already known
        s.expire(1)
        m.event(kind: "agent.started")
        try? await Task.sleep(for: .milliseconds(50))
        #expect(host.shell.toast == nil)  // not a connection event
        m.event(kind: "connection.health")
        for _ in 0..<200 where host.shell.toast == nil { try? await Task.sleep(for: .milliseconds(2)) }
        #expect(host.shell.toast?.message.hasPrefix("Personal GitHub needs you.") == true)
        #expect(notes == ["connection-1"])
    }

    @Test func theLoopbackTakesOnlyItsOwnCallback() {
        #expect(
            LoopbackCatcher.code(in: "GET /callback?code=abc&state=s1 HTTP/1.1\r\nHost: x\r\n", state: "s1") == "abc")
        #expect(LoopbackCatcher.code(in: "GET /callback?code=abc&state=other HTTP/1.1\r\n", state: "s1") == nil)
        #expect(LoopbackCatcher.code(in: "GET /favicon.ico HTTP/1.1\r\n", state: "s1") == nil)
        #expect(LoopbackCatcher.code(in: "POST /callback?code=abc&state=s1 HTTP/1.1\r\n", state: "s1") == nil)
        #expect(LoopbackCatcher.code(in: "GET /callback?state=s1 HTTP/1.1\r\n", state: "s1") == nil)
    }

    @Test func theLoopbackAnswersTheBrowserAndHandsOnTheCode() async throws {
        let got = Got()
        let c = try LoopbackCatcher(state: "s1") { code in Task { await got.set(code) } }
        c.start()
        defer { c.stop() }
        try await Task.sleep(for: .milliseconds(100))
        let url = URL(string: "http://127.0.0.1:\(LoopbackCatcher.port)/callback?code=xyz&state=s1")!
        let (data, resp) = try await URLSession.shared.data(from: url)
        #expect((resp as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self).contains("You can close this tab"))
        for _ in 0..<100 where await got.code == nil { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await got.code == "xyz")
    }
}

private actor Got {
    var code: String?
    func set(_ c: String) { code = c }
}

@MainActor
struct ConnectionsKeysTests {
    @Test func arrowsWalkTheCardsInDrawnOrderAndStopAtTheEnds() async {
        let host = FakeHost()
        let m = ConnectionsModel(host: host)
        m.use(SampleConnections())
        await m.reload()
        m.move(1)
        #expect(m.cursor == 1)
        m.move(1)
        m.move(1)
        m.move(1)
        #expect(m.cursor == 3)
        m.move(-1)
        #expect(m.cursor == 2)
        #expect(m.key("x") == false)
    }
}
