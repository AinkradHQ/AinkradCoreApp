import CoreKit
import Foundation
import Testing

@testable import Accounts

private let github = SampleConnections.kinds[0]
private let slack = SampleConnections.kinds[3]

/// The step machine of the guided Add (D-21), the access sentences and the state chips: pure values.
struct ConnAddStateTests {
    @Test func aServiceTileMovesOnToSigningIn() {
        var a = ConnAddState()
        #expect(a.step == .service && a.kind == nil)
        a.pick(service: "github")
        #expect(a.step == .signIn && a.kind == "github" && a.connection == nil)
        // Opening on a named service skips the tiles.
        #expect(ConnAddState(kind: "slack").step == .signIn)
    }

    @Test func aFinishedSignInGoesToWhatAIMayDoAndASecondSignInStraightToDone() {
        var a = ConnAddState(kind: "github")
        a.signedIn(connection: 7)
        #expect(a.step == .allow && a.connection == 7)
        var again = ConnAddState(kind: "github")
        again.again = true
        again.signedIn(connection: 7)
        #expect(again.step == .done)
    }

    @Test func readOnlyAllowsOnlyTheReadCapabilitiesAndWriteTurnsTheOthersOn() {
        var a = ConnAddState(kind: "github")
        #expect(a.mode == .read && a.allowed(github) == ["read_repo"])
        a.toggle("push")  // dimmed in read mode: ignored
        #expect(a.writes.isEmpty)
        a.set(mode: .write, in: github)
        #expect(a.allowed(github) == ["read_repo", "pr_write", "push"])
        a.toggle("push")
        #expect(a.allowed(github) == ["read_repo", "pr_write"] && a.mode == .write)
        a.toggle("pr_write")  // the last write off is read only again
        #expect(a.mode == .read && a.allowed(github) == ["read_repo"])
        a.set(mode: .write, in: github)
        a.set(mode: .read, in: github)
        #expect(a.writes.isEmpty)
    }

    @Test func theFirstCapabilityIsAlwaysOn() {
        let a = ConnAddState(kind: "slack")
        #expect(a.isOn(slack.capabilities[0]) && !a.isOn(slack.capabilities[1]))
    }

    @Test func theListIsSearchedByNameIdAndSecondLineAndNeedsOnePick() {
        let all = [
            ConnPick(id: "maple/harbor-web", name: "maple/harbor-web"),
            ConnPick(id: "HAR", name: "Harbor", detail: "HAR"),
            ConnPick(id: "C2", name: "#build", detail: "14 people"),
        ]
        var a = ConnAddState(kind: "github")
        #expect(a.visible(all).count == 3)
        a.query = " HARBOR "
        #expect(a.visible(all).map(\.id) == ["maple/harbor-web", "HAR"])
        a.query = "14 peo"
        #expect(a.visible(all).map(\.id) == ["C2"])
        #expect(!a.canFinish && a.countLine == "0 picked")
        a.toggle(pick: "C2")
        #expect(a.canFinish && a.countLine == "1 picked")
        a.toggle(pick: "C2")
        #expect(!a.canFinish)
    }

    @Test func theSavedIdsFollowTheListOrderThenAnyTheListNoLongerShows() {
        var a = ConnAddState(kind: "github")
        a.picked = ["z/gone", "b", "a"]
        let order = [ConnPick(id: "a", name: "a"), ConnPick(id: "c", name: "c"), ConnPick(id: "b", name: "b")]
        #expect(a.chosen(order: order) == ["a", "b", "z/gone"])
    }

    @Test func pastSixtyFourAFullyTickedOwnerIsSavedAsAWildcardAndComesBackTicked() {
        var a = ConnAddState(kind: "github")
        let mine = (0..<70).map { ConnPick(id: "me/r\($0)", name: "r\($0)") }
        let org = [ConnPick(id: "org/x", name: "x"), ConnPick(id: "org/y", name: "y")]
        a.picked = Set(mine.map(\.id) + ["org/x"])
        #expect(a.chosen(order: mine + org) == ["me/*", "org/x"])
        #expect(a.chosen(order: mine + org, complete: false).count == 71)
        a.picked = ["me/*", "org/x"]
        a.expandWildcards(mine + org, complete: true)
        #expect(a.picked == Set(mine.map(\.id) + ["org/x"]))
    }

    @Test func stepsGoForwardAndBackAndDoneHasNoBack() {
        var a = ConnAddState(kind: "github")
        a.signedIn(connection: 1)
        a.next()
        #expect(a.step == .choose)
        a.next()
        #expect(a.step == .done)
        a.back()
        #expect(a.step == .done)
        a.step = .choose
        a.back()
        #expect(a.step == .allow)
        a.back()  // the sign-in is done, so back is the tiles
        #expect(a.step == .service)
    }

    @Test func editingNeverGoesBackPastTheStepItOpenedOn() {
        let c = ConnItem(
            id: 1, kind: "github", name: "n", identity: "@maple-fox", status: .connected, isDefault: true,
            allowed: ["read_repo", "push"], only: ["a/b"], users: 1)
        var a = ConnAddState(editing: c, kind: github, at: .allow)
        #expect(a.mode == .write && a.writes == ["push"] && a.picked == ["a/b"] && a.editing)
        a.back()
        #expect(a.step == .allow)
        a.next()
        a.back()
        #expect(a.step == .allow)
    }

    @Test func theLastStepSaysWhatWasAllowedInWords() {
        var a = ConnAddState(kind: "github")
        a.picked = ["a", "b", "c"]
        #expect(a.doneLine(noun: "repositories") == "Your assistant can read 3 repositories. Nothing can be changed.")
        a.set(mode: .write, in: github)
        a.picked = ["a"]
        #expect(a.doneLine(noun: "repositories") == "Your assistant can read and change 1 repository.")
    }
}

struct ConnAccessTests {
    @Test func theLeadSaysReadOnlyPostingOrChanges() {
        #expect(ConnAccess.lead(github, allowed: ["read_repo"]) == "Read only")
        #expect(ConnAccess.lead(github, allowed: ["read_repo", "push"]) == "Can make changes")
        #expect(ConnAccess.lead(slack, allowed: ["read_messages", "post_messages"]) == "Can post messages")
        #expect(ConnAccess.lead(slack, allowed: []) == "Not allowed yet")
    }

    @Test func theScopeCountsWhatIsReached() {
        #expect(ConnAccess.scope(github, only: ["a", "b", "c"]) == "3 repositories")
        #expect(ConnAccess.scope(github, only: ["a"]) == "1 repository")
        #expect(ConnAccess.scope(github, only: nil) == "All repositories")
        #expect(ConnAccess.scope(slack, only: []) == "No channels")
        #expect(ConnAccess.noun("projects", count: 1) == "project")
        #expect(ConnAccess.noun("teams", count: 2) == "teams")
    }

    @Test func updatedWordsMatchTheMockup() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func ago(_ days: Double) -> String { ConnAccess.updated(now.addingTimeInterval(-86_400 * days - 60), now: now) }
        #expect(ago(0) == "Updated today")
        #expect(ago(1) == "Updated yesterday")
        #expect(ago(3) == "3 days ago")
        #expect(ago(8) == "Last week")
        #expect(ago(30) == "Last month")
        #expect(ago(90) == "3 months ago")
        #expect(ConnAccess.line(ConnPick(id: "a", name: "a", detail: "HAR"), now: now) == "HAR")
    }
}

struct ConnChipTests {
    private func item(_ status: ConnStatus, signIn: Bool = false) -> ConnItem {
        ConnItem(
            id: 1, kind: "github", name: "n", identity: "i", status: status, isDefault: false, allowed: [], only: nil,
            users: 1, signInNeeded: signIn)
    }

    @Test func aRowIsConnectedSignInAgainOrWhatElseNeedsALook() {
        #expect(ConnLook.chip(item(.connected)).0 == "Connected")
        #expect(ConnLook.chip(item(.needsLook, signIn: true)).0 == "Sign in again")
        #expect(ConnLook.chip(item(.needsLook)).0 == "Needs a look")
        #expect(ConnLook.chip(item(.disabled)).0 == "Turned off")
    }
}

/// The model side: the dialog walks the steps against the sample Core.
@MainActor
struct ConnAddModelTests {
    func make() async -> (ConnectionsModel, SampleConnections, FakeHost) {
        let host = FakeHost()
        let m = ConnectionsModel(host: host)
        m.opener = { _ in }
        m.pollEvery = .milliseconds(1)
        let s = SampleConnections()
        m.use(s)
        await m.reload()
        return (m, s, host)
    }

    private func settle(_ m: ConnectionsModel, until done: () -> Bool) async {
        for _ in 0..<500 where !done() { try? await Task.sleep(for: .milliseconds(2)) }
    }

    @Test func aSignInMovesTheDialogToWhatAIMayDoThenSavesTheGrantAtTheEnd() async {
        let (m, s, host) = await make()
        m.add = ConnAddState()
        m.pick(service: "slack")
        await settle(m) { m.add?.step == .allow }
        #expect(m.add?.step == .allow)
        let id = try! #require(m.add?.connection)
        // Nothing is allowed until the last step: a sign-in alone gives AI no access.
        await m.reload()
        #expect(m.item(id)?.allowed.isEmpty == true)
        m.add?.set(mode: .write, in: m.kind("slack"))
        m.addNext()
        await settle(m) { if case .ready = m.picks { true } else { false } }
        m.add?.toggle(pick: "C02")
        await m.finishAdd()
        #expect(m.add?.step == .done)
        #expect(m.item(id)?.allowed == ["read_messages", "post_messages"])
        #expect(m.item(id)?.only == ["C02"])
        #expect(host.reasons.last == "Change what AI sessions may do with \(m.item(id)!.name).")
        _ = s
    }

    @Test func nothingPickedSavesNothing() async {
        let (m, _, host) = await make()
        m.beginEdit(m.items[0], at: .choose)
        m.add?.picked = []
        await m.finishAdd()
        #expect(m.add?.step == .choose)
        #expect(!host.reasons.contains { $0.hasPrefix("Change what AI") })
    }

    @Test func aDeclinedTouchIDKeepsTheStepAndSaysWhy() async {
        let (m, _, host) = await make()
        m.beginEdit(m.items[0], at: .choose)
        await m.loadPicks()
        m.add?.picked = ["maple/harbor-web"]
        host.declines = true
        await m.finishAdd()
        #expect(m.add?.step == .choose)
        #expect(m.item(1)?.only == nil)
    }

    @Test func aFailedListSaysSoAndCanBeReadAgain() async {
        let (m, s, _) = await make()
        s.failPicks = true
        m.beginEdit(m.items[0], at: .choose)
        await m.loadPicks()
        guard case .failed(let why) = m.picks else {
            Issue.record("expected a failure")
            return
        }
        #expect(!why.isEmpty)
        s.failPicks = false
        await m.loadPicks()
        #expect(m.picks != .loading)
    }

    @Test func changingAccessOnAConnectionThatReachedEverythingStartsWithEverythingTicked() async {
        let (m, _, _) = await make()
        m.beginEdit(m.items[0], at: .allow)
        #expect(m.add?.picked.isEmpty == true)
        await m.loadPicks()
        #expect(m.add?.picked.count == 6)
    }

    @Test func disconnectGoesFromTheListAtOnceAndOnlyDeletesAfterTheUndoWindow() async {
        let (m, _, _) = await make()
        m.undoWindow = .milliseconds(80)
        let c = m.items[2]
        m.disconnectWithUndo(c)
        #expect(m.shown.contains { $0.id == c.id } == false)
        #expect(m.item(c.id) != nil, "the Core still has it inside the window")
        await settle(m) { m.item(c.id) == nil }
        #expect(m.item(c.id) == nil)
    }

    @Test func undoBringsItBackAndNeverDeletes() async {
        let (m, _, _) = await make()
        m.undoWindow = .milliseconds(80)
        let c = m.items[2]
        m.disconnectWithUndo(c)
        m.undoDisconnect(c.id)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(m.shown.contains { $0.id == c.id })
        #expect(m.item(c.id) != nil)
    }

    @Test func disconnectingADefaultClearsItFirstSoTheCoreAccepts() async {
        let (m, _, _) = await make()
        let d = m.items.first { $0.isDefault }!
        #expect(await m.disconnect(d))
        #expect(m.item(d.id) == nil)
    }

    @Test func signInAgainReplacesTheCredentialAndEndsOnDone() async {
        let (m, _, _) = await make()
        let c = m.items[1]
        m.beginAgain(c)
        #expect(m.add?.again == true && m.add?.connection == c.id)
        await settle(m) { m.add?.step == .done }
        #expect(m.add?.step == .done)
    }
}
