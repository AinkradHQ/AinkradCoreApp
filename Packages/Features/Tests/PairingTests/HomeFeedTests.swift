import Agents
import CoreUI
import Foundation
import Shell
import Testing
import os

@testable import Pairing

private struct FakeHome: HomeSource {
    var sessionList: [AgentSessionInfo] = []
    var runnerList: [HomeRunner] = []
    var costList: [(at: Date, micros: Int64)] = []
    var share = 0.0
    var auditList: [HomeAudit] = []
    var denied = false
    /// How many times Home read the sessions: one per refresh.
    let reads = OSAllocatedUnfairLock(initialState: 0)

    func sessions() async throws -> [AgentSessionInfo] {
        reads.withLock { $0 += 1 }
        return sessionList
    }
    func runners() async throws -> [HomeRunner] { runnerList }
    func costs() async throws -> [(at: Date, micros: Int64)] {
        if denied { throw URLError(.userAuthenticationRequired) }
        return costList
    }
    func utilisation() async throws -> Double { share }
    func audit() async throws -> [HomeAudit] { auditList }
    func health() async throws -> CoreHealthFacts {
        if let healthFacts { return healthFacts }
        throw URLError(.cannotConnectToHost)
    }
    var healthFacts: CoreHealthFacts?
}

@MainActor @Suite struct HomeFeedTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(_ id: String, _ state: SessionState, ago: TimeInterval) -> AgentSessionInfo {
        AgentSessionInfo(
            id: id, runner: "r", harness: "claude-code", model: "opus", state: state,
            createdAt: now.addingTimeInterval(-ago), updatedAt: now)
    }

    @Test func coreAnswersBecomeTheSnapshot() async {
        let shell = ShellModel(defaults: UserDefaults(suiteName: "feed-\(UUID())")!)
        let src = FakeHome(
            sessionList: [session("a", .running, ago: 600), session("b", .ended, ago: 60)],
            runnerList: [HomeRunner(name: "mini", arch: "arm64", online: true, capacity: 4, load: 2, perCore: 0.25)],
            costList: [(now, 1_500_000), (now.addingTimeInterval(-3 * 86_400), 9_000_000)],
            share: 0.4,
            auditList: [HomeAudit(seq: 7, at: now.addingTimeInterval(-300), action: "device.revoked", actor: "Core")])
        let feed = HomeFeed(shell: shell, source: src, now: { [now] in now })
        await feed.refresh()
        let h = shell.home
        #expect(h.running.map(\.id) == ["a"])
        #expect(h.running.first?.minutes == 10)
        #expect(h.machines.first?.id == "mini")
        #expect(h.machines.first?.slots == 4)
        #expect(h.machines.first?.loadPercent == 25)
        #expect(h.spendToday == 1.5)
        #expect(h.monthTokensUsed == 0.4)
        #expect(h.events.first?.text == "Device revoked")
        #expect(h.events.first?.minutesAgo == 5)
    }

    @Test func coreHealthBecomesTheWidgetValues() async {
        let shell = ShellModel(defaults: UserDefaults(suiteName: "feed-\(UUID())")!)
        var src = FakeHome()
        src.healthFacts = CoreHealthFacts(
            version: "0.2.1", uptimeSecs: 90_000, certDaysLeft: 62, lastBackupAt: now.addingTimeInterval(-3 * 3600),
            lastBackupBytes: 4_000_000)
        await HomeFeed(shell: shell, source: src, now: { [now] in now }).refresh()
        let h = shell.home.health
        #expect(h?.version == "0.2.1" && h?.certificate == "62 days" && h?.uptime == "1 day 1 hour")
        #expect(h?.backupAge(now: now) == "3 hours ago")
        // A Core that does not answer /core/health leaves the rest of Home showing.
        let none = ShellModel(defaults: UserDefaults(suiteName: "feed-\(UUID())")!)
        await HomeFeed(shell: none, source: FakeHome(), now: { [now] in now }).refresh()
        #expect(none.home.health == nil)
    }

    @Test func aRefusedReadLeavesTheRestShowing() async {
        let shell = ShellModel(defaults: UserDefaults(suiteName: "feed-\(UUID())")!)
        var src = FakeHome(sessionList: [session("a", .running, ago: 60)])
        src.denied = true
        await HomeFeed(shell: shell, source: src, now: { [now] in now }).refresh()
        #expect(shell.home.runningAgents == 1)
        #expect(shell.home.spendToday == 0)
    }

    @Test func onlyHomeEventsRefreshAfterAQuietMoment() async throws {
        let shell = ShellModel(defaults: UserDefaults(suiteName: "feed-\(UUID())")!)
        let src = FakeHome(sessionList: [session("a", .running, ago: 60)])
        let feed = HomeFeed(shell: shell, source: src, quiet: .milliseconds(20))
        // Not a Home event: nothing is scheduled, so nothing is read.
        feed.event(kind: "device.added")
        // Two Home events in a row make one refresh.
        feed.event(kind: "agent.session.started")
        feed.event(kind: "agent.session.updated")
        #expect(await until { shell.home.runningAgents == 1 })
        #expect(src.reads.withLock { $0 } == 1, "the device event read nothing, the two agent events read once")
    }

    @Test func pairingEventsRefreshHomeAndReadInPlainWords() async throws {
        let shell = ShellModel(defaults: UserDefaults(suiteName: "feed-\(UUID())")!)
        let src = FakeHome(auditList: [
            HomeAudit(seq: 2, at: now, action: "pairing.approved", actor: "User 1"),
            HomeAudit(seq: 1, at: now, action: "pairing.claimed", actor: "Core"),
        ])
        let feed = HomeFeed(shell: shell, source: src, quiet: .milliseconds(20), now: { [now] in now })
        feed.event(kind: "pairing.claimed")
        #expect(await until { shell.home.events.count == 2 })
        #expect(shell.home.events.map(\.text) == ["Pairing approved", "Pairing claimed"])
    }
}
