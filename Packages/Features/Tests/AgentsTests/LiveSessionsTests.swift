import CoreUI
import Foundation
import Testing

@testable import Agents

/// The AI Sessions list (variant B), the live conversation's pure parts, and the new entry kinds.
struct LiveSessionsTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(
        _ id: String, _ state: SessionState, ageDays: Double = 0, harness: String = "claude", runner: String = "r1",
        cost: Int64? = nil, project: String? = nil
    ) -> AgentSessionInfo {
        let at = now.addingTimeInterval(-ageDays * 86_400)
        return AgentSessionInfo(
            id: id, runner: runner, harness: harness, state: state, createdAt: at, updatedAt: at,
            usage: cost.map { AgentUsageInfo(input: 1, output: 1, costMicros: $0) }, project: project)
    }

    private func index(
        _ items: [AgentSessionInfo], needs: Set<String> = [], pinned: Set<String> = [], archived: Set<String> = []
    ) -> SessionIndex {
        SessionIndex(
            .init(
                items: items, needsYou: needs, pinned: pinned, archived: archived, now: now, calendar: cal,
                title: { $0.id }, runnerName: { $0 }, project: { $0.project }))
    }

    @Test func activeHasNeedsYouRunningWaitingAndPinnedOnTop() {
        let items = [
            session("run", .running), session("wait", .waiting), session("need", .running), session("pin", .waiting),
            session("old", .ended, ageDays: 1),
        ]
        let g = index(items, needs: ["need"], pinned: ["pin"]).groups(scope: .active, filters: .init())
        #expect(g.map(\.section) == [.pinned, .needsYou, .running, .waiting])
        #expect(g[0].rows.map(\.id) == ["pin"])
        #expect(g[3].rows.map(\.id) == ["wait"])
    }

    @Test func endedSessionsArchiveAfterFourteenDaysAndEarlierIsEightToFourteen() {
        let items = [
            session("t", .ended), session("y", .ended, ageDays: 1), session("w", .ended, ageDays: 5),
            session("e8", .ended, ageDays: 8), session("e14", .ended, ageDays: 14), session("a15", .ended, ageDays: 15),
            session("liveOld", .waiting, ageDays: 30),
        ]
        let i = index(items)
        #expect(i.counts[.today] == 1 && i.counts[.yesterday] == 1 && i.counts[.thisWeek] == 1)
        #expect(i.counts[.earlier] == 3)  // e8, e14 and the live one that is never archived
        #expect(i.counts[.archive] == 1)
        #expect(i.groups(scope: .archive, filters: .init()).flatMap(\.rows).map(\.id) == ["a15"])
        #expect(!i.flat(scope: .earlier, filters: .init()).contains { $0.id == "a15" })
    }

    @Test func archivingByHandAndSearchReachingTheArchive() {
        let items = [session("keep", .ended), session("gone", .ended)]
        let i = index(items, archived: ["gone"])
        #expect(i.counts[.archive] == 1)
        #expect(i.flat(scope: .today, filters: .init()).map(\.id) == ["keep"])
        var f = SessionFilters()
        f.search = "gone"
        #expect(i.flat(scope: .active, filters: f).map(\.id) == ["gone"])
    }

    @Test func filtersNarrowByToolRunnerProjectAndState() {
        let items = [
            session("a", .running, harness: "claude", runner: "r1", project: "Core"),
            session("b", .waiting, harness: "codex", runner: "r2", project: "App"),
        ]
        let i = index(items)
        var f = SessionFilters()
        f.tool = "codex"
        #expect(i.flat(scope: .active, filters: f).map(\.id) == ["b"])
        f = SessionFilters()
        f.runner = "r1"
        #expect(i.flat(scope: .active, filters: f).map(\.id) == ["a"])
        f = SessionFilters()
        f.project = "App"
        #expect(i.flat(scope: .active, filters: f).map(\.id) == ["b"])
        f = SessionFilters()
        f.state = .waiting
        #expect(i.flat(scope: .active, filters: f).map(\.id) == ["b"])
        #expect(i.projects.map(\.name) == ["App", "Core"])
    }

    @Test func fiveHundredSessionsGroupQuickly() {
        let items = (0..<500).map { session("s\($0)", $0 % 3 == 0 ? .running : .ended, ageDays: Double($0 % 20)) }
        let t = Date()
        let i = index(items)
        let n = i.groups(scope: .active, filters: .init()).flatMap(\.rows).count
        #expect(n == 167)
        #expect(Date().timeIntervalSince(t) < 1)
    }

    @Test func sectionCostsAddUp() {
        let g = index([session("a", .running, cost: 500_000), session("b", .running, cost: 250_000)])
            .groups(scope: .active, filters: .init())
        #expect(g.first?.costMicros == 750_000)
    }

    @Test func aWaitingSessionIsLive() {
        #expect(session("w", .waiting).live && session("w", .waiting).idle)
        #expect(!session("e", .ended).live)
        #expect(AgentWords.status(session("w", .waiting), waiting: false).label == "Waiting for you")
    }

    // MARK: the conversation's parts

    @Test func diffShowsRemovedAndAddedLinesWithContext() {
        let d = DiffLines.make(old: "a\nb\nc\nd", new: "a\nb\nX\nY\nd")
        #expect(d.filter { $0.kind == .removed }.map(\.text) == ["c"])
        #expect(d.filter { $0.kind == .added }.map(\.text) == ["X", "Y"])
        #expect(d.first?.kind == .context)
        let w = DiffLines.make(old: "", new: "one\ntwo")
        #expect(w.map(\.kind) == [.added, .added])
    }

    @Test func entryParserKeepsEditsAndTodosAndTurnEnds() {
        let edit = EntryParser.kind([
            "type": "tool_use", "id": "t1", "name": "Edit",
            "input": ["file_path": "/a/b.rs", "old_string": "x", "new_string": "y"],
        ])
        #expect(
            edit == .toolEdit(id: "t1", name: "Edit", path: "/a/b.rs", old: "x", new: "y", ok: nil, durationMs: nil))
        let todo = EntryParser.kind([
            "type": "tool_use", "id": "t2", "name": "TodoWrite",
            "input": [
                "todos": [["content": "one", "status": "completed"], ["content": "two", "status": "in_progress"]]
            ],
        ])
        #expect(
            todo
                == .toolTodos(
                    id: "t2",
                    items: [TodoItem(text: "one", status: .completed), TodoItem(text: "two", status: .inProgress)]))
        // The runner's real usage entry: this turn's tokens, and the session's cost so far in dollars.
        let turn = EntryParser.kind([
            "type": "usage", "input": 4, "output": 207, "cache_read": 32422, "cache_write": 6411,
            "cost_usd": 0.00171032,
        ])
        #expect(turn == .turnEnded(costMicros: 1710, tokens: 211))
        #expect(
            EntryParser.kind(["type": "usage", "input": 0, "output": 0, "cost_usd": NSNull()])
                == .turnEnded(costMicros: nil, tokens: nil))
    }

    @Test func idleEndedSessionsReadAsEndedAndTakeAMessage() {
        var s = session("i", .ended)
        s.outcome = .succeeded
        s.outcomeReason = "idle_timeout"
        #expect(s.idleEnded && AgentWords.status(s, waiting: false).label == "Ended (idle)")
        #expect(AgentWords.reasonWords("idle_timeout").contains("Send a message"))
    }

    @MainActor @Test func aResultJoinsItsEditAndTodoAnswersAreDropped() {
        let store = TranscriptStore(sessionID: "s")
        let t = Date()
        store.append([
            TranscriptEntry(
                seq: 1, at: t,
                kind: .toolEdit(id: "e", name: "Edit", path: "/p", old: "a", new: "b", ok: nil, durationMs: nil)),
            TranscriptEntry(
                seq: 2, at: t,
                kind: .toolResult(id: "e", name: nil, ok: true, exitCode: nil, output: "", durationMs: 100)),
            TranscriptEntry(seq: 3, at: t, kind: .toolTodos(id: "d", items: [])),
            TranscriptEntry(
                seq: 4, at: t,
                kind: .toolResult(id: "d", name: nil, ok: true, exitCode: nil, output: "ok", durationMs: 1)),
            TranscriptEntry(seq: 5, at: t, kind: .turnEnded(costMicros: 5, tokens: nil)),
        ])
        #expect(store.entries.count == 3)
        #expect(
            store.entries[0].kind
                == .toolEdit(id: "e", name: "Edit", path: "/p", old: "a", new: "b", ok: true, durationMs: 100))
    }

    @MainActor @Test func cumulativeCostBecomesEachTurnsOwn() {
        let store = TranscriptStore(sessionID: "s")
        let t = Date()
        func usage(_ seq: Int64, _ micros: Int64?) -> TranscriptEntry {
            TranscriptEntry(seq: seq, at: t, kind: .turnEnded(costMicros: micros, tokens: 10))
        }
        store.append([usage(1, 1_000), usage(2, 4_500), usage(3, nil), usage(4, 4_500)])
        let costs = store.entries.map { e -> Int64? in if case .turnEnded(let c, _) = e.kind { c } else { nil } }
        // The first turn held has nothing to subtract from, so it shows no cost; the rest are the differences.
        #expect(costs == [nil, 3_500, nil, 0])
    }

    @Test func markdownTablesQuotesAndHighlighting() {
        let md = "| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n\n> quoted\n\ntext"
        #expect(
            MarkdownBlock.parse(md) == [
                .table(header: ["a", "b"], rows: [["1", "2"], ["3", "4"]]), .quote("quoted"), .paragraph("text"),
            ])
        let t = SyntaxHighlight.tokens("let x = \"hi\" // c")
        #expect(t.contains { $0 == ("let", .keyword) } && t.contains { $0 == ("\"hi\"", .string) })
        #expect(t.last?.1 == .comment)
    }

    @Test func slashCommandsFilterByWhatIsTyped() {
        #expect(SlashCommands.matches("/co").map(\.name) == ["/compact", "/context", "/cost"])
        #expect(SlashCommands.matches("/compact now").isEmpty && SlashCommands.matches("hi").isEmpty)
        #expect(SlashCommands.matches("/").count == SlashCommands.all.count)
    }
}

@Suite struct ContextWindowTests {
    @Test func windowComesFromTheModelId() {
        #expect(ContextWindow.tokens(model: "claude-opus-4-7[1m]") == 1_000_000)
        #expect(ContextWindow.tokens(model: "claude-sonnet-4-5") == 200_000)
        #expect(ContextWindow.tokens(model: "gpt-5-codex") == 400_000)
        #expect(ContextWindow.tokens(model: nil) == 200_000)
    }
}

@Suite struct WorkspaceWireTests {
    @Test func theSheetsRepoBecomesTheCoresWorkspace() throws {
        let none = NewAgentSession(runner: "d_1", harness: "claude", prompt: "")
        #expect(try LiveAgentsAPI.workspace(none) == nil)
        let repo = NewAgentSession(
            runner: "d_1", harness: "claude", prompt: "", project: "https://github.com/AinkradHQ/AinkradCore.git",
            branch: "feat/x", base: "development")
        let w = try #require(try LiveAgentsAPI.workspace(repo)?.value)
        #expect(w["repo"] as? String == "https://github.com/AinkradHQ/AinkradCore.git")
        #expect(w["base"] as? String == "development" && w["branch"] as? String == "feat/x")
        // No branch named: the session works on the base; no base: main.
        let bare = NewAgentSession(runner: "d_1", harness: "claude", prompt: "", project: "/srv/repo")
        let b = try #require(try LiveAgentsAPI.workspace(bare)?.value)
        #expect(b["base"] as? String == "main" && b["branch"] as? String == "main")
    }

    @Test func projectsAreNamedByTheirRepo() {
        #expect(LiveAgentsAPI.projectName("https://github.com/AinkradHQ/AinkradCore.git") == "AinkradCore")
        #expect(LiveAgentsAPI.projectName("git@github.com:AinkradHQ/AinkradCoreApp.git") == "AinkradCoreApp")
        #expect(LiveAgentsAPI.projectName("/Users/me/code/acme-shop/") == "acme-shop")
    }
}
