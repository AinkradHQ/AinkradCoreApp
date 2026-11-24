import Foundation
import Testing

@testable import Accounts

private let github = SampleConnections.kinds[0]
private let jira = SampleConnections.kinds[1]

private func flow(code: String?, _ step: ConnFlow.Step, kind: String = "github") -> ConnFlow {
    ConnFlow(
        id: "f", kind: kind, userCode: code, url: URL(string: "https://github.com/login/device")!, step: step)
}

/// The sign-in checklist ticks only what the app knows, and the redesign's pure helpers.
struct ConnRedesignTests {
    @Test func deviceCodeChecklistFollowsCopyAndTheFlow() {
        let w = flow(code: "74F2-8568", .waiting)
        var items = ConnSignIn.items(kind: github, flow: w, copied: false)
        #expect(items.map(\.state) == [.current, .todo, .todo])
        #expect(items[1].detail == "github.com/login/device" && items[2].detail == "Waiting for GitHub…")
        items = ConnSignIn.items(kind: github, flow: w, copied: true)
        #expect(items.map(\.state) == [.done, .current, .todo])
        // Pasting and approving happen on GitHub's page: only the flow saying connected ticks them.
        items = ConnSignIn.items(kind: github, flow: flow(code: "74F2-8568", .connected(1)), copied: false)
        #expect(items.map(\.state) == [.done, .done, .done])
    }

    @Test func browserChecklistHasNoCopyAndTicksPickOnlyWhenTheFlowIsThere() {
        var items = ConnSignIn.items(kind: jira, flow: flow(code: nil, .waiting, kind: "jira"), copied: true)
        #expect(items.map(\.title) == ["Sign in to Atlassian", "Pick your site", "Approve Ainkrad"])
        #expect(items.map(\.state) == [.current, .todo, .todo])
        items = ConnSignIn.items(kind: jira, flow: flow(code: nil, .pickSite(["a"]), kind: "jira"), copied: false)
        #expect(items.map(\.state) == [.done, .current, .todo])
        // The flow has not come back from the Core yet: nothing is ticked.
        #expect(ConnSignIn.items(kind: jira, flow: nil, copied: false).map(\.state) == [.current, .todo, .todo])
    }

    @Test func selectAllAndClearAllTouchOnlyTheRowsShown() {
        let rows = [ConnPick(id: "a", name: "a"), ConnPick(id: "b", name: "b")]
        var s = ConnAddState(kind: "github")
        s.picked = ["z"]
        #expect(!s.allPicked(rows))
        s.selectAll(rows)
        #expect(s.picked == ["a", "b", "z"] && s.allPicked(rows))
        s.clearAll(rows)
        #expect(s.picked == ["z"] && !s.allPicked([]))
    }

    @Test func theMainButtonNamesTheCount() {
        var s = ConnAddState(kind: "github")
        #expect(s.finishTitle(noun: "repositories", saving: false) == "Connect")
        s.picked = ["a"]
        #expect(s.finishTitle(noun: "repositories", saving: false) == "Connect 1 repository")
        s.picked = ["a", "b"]
        #expect(s.finishTitle(noun: "repositories", saving: false) == "Connect 2 repositories")
        #expect(s.finishTitle(noun: "repositories", saving: true) == "Saving…")
    }

    @Test func backIsOfferedOnlyWhereItMoves() {
        var s = ConnAddState()
        #expect(!s.canGoBack)
        s.pick(service: "github")
        #expect(s.canGoBack)  // sign in goes back to the cards
        s.signedIn(connection: 1)
        #expect(s.canGoBack)
        s.step = .done
        #expect(!s.canGoBack)
        // An edit opened on Access never goes before it.
        let c = ConnItem(
            id: 1, kind: "github", name: "g", identity: "me", status: .connected, isDefault: false, allowed: [],
            only: nil, users: 1)
        var e = ConnAddState(editing: c, kind: github, at: .allow)
        #expect(!e.canGoBack)
        e.next()
        #expect(e.canGoBack)
    }

    @Test func lastUsedReadsInPlainWords() {
        let now = Date()
        #expect(ConnAccess.used(now.addingTimeInterval(-20), now: now) == "Just now")
        #expect(ConnAccess.used(now.addingTimeInterval(-12 * 60), now: now) == "12 min ago")
        #expect(ConnAccess.used(now.addingTimeInterval(-86400 * 3), now: now) == "3 days ago")
    }

    @Test func heroLightRunsOneWireAtATimeAndRestsUnderReduceMotion() {
        #expect(ConnHeroGeometry.light(at: 0.5, count: 5, reduce: true) == nil)
        #expect(ConnHeroGeometry.light(at: 2.0, count: 5, reduce: false) == nil)  // between runs
        let l = ConnHeroGeometry.light(at: ConnHeroGeometry.lightPeriod + 0.6, count: 5, reduce: false)
        #expect(l?.wire == 1 && abs((l?.progress ?? 0) - 0.5) < 0.001)
        #expect(ConnHeroGeometry.light(at: 1, count: 0, reduce: false) == nil)
    }
}
