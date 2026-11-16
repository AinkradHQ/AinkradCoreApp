#if DEBUG
import AppKit
import Foundation

/// Debug only: a demo session that holds every kind of content a session can show (Ahmed, 2026-11-15: "show me all types of
/// data in the session"), so each renderer can be seen and checked in one place.
extension FakeAgentsAPI {
    public static func addShowcase(to api: FakeAgentsAPI, now: Date = Date()) {
        let photo = demoImage("showcase-screenshot", hue: 0.55)
        let chart = demoImage("showcase-chart", hue: 0.38, bars: true)
        let s = AgentSessionInfo(
            id: "as_01JC4X7Q3MZ8N5V2K9R020", runner: "d_mac", harness: "claude", state: .running, outcome: nil,
            createdAt: now.addingTimeInterval(-900), updatedAt: now.addingTimeInterval(-20), endedAt: nil, lastSeq: 0,
            usage: AgentUsageInfo(input: 74_000, output: 14_400, costMicros: 1_480_000), index: 20)
        let report = """
            # Runner fleet status
            Three of four runners are online. **build-box** has been offline since Friday; the others are healthy.

            ## Load
            | Runner | State | AI sessions | Load |
            |---|---|---|---|
            | mac-studio | Online | 2 of 4 | 48% |
            | linux-01 | Online | 2 of 2 | 91% |
            | home-server | Online | 1 of 2 | 35% |
            | build-box | Offline | 0 of 2 | — |

            ![Load over the last 7 days](\(chart?.path ?? ""))

            ## What needs attention
            1. **linux-01** is full: new sessions queue behind it.
            2. **build-box** needs a restart from its host.
            - Backups are current (last one 3 h ago).
            - The certificate has 41 days left.

            > Moving one session from linux-01 to home-server frees a slot right away.

            ---
            The check that produced this:
            ```sh
            ainkradctl runners list --json | jq '.[] | {name, load}'
            ```
            See the [runner guide](https://example.com/runners) for the restart steps.
            """
        let plan = """
            ## Next sprint: queue fairness
            1. Measure how long sessions wait today (one day of data).
            2. Add a per-account queue so one account cannot fill a runner.
            3. Show the queue position in the session header.

            | Step | Owner | Size |
            |---|---|---|
            | Measure | Core | S |
            | Per-account queue | Core | M |
            | Queue position | App | S |

            Nothing changes for running sessions; the queue only orders new ones.
            """
        api.add(
            s,
            entries: [
                .started(harness: "claude", resumed: false),
                .user(
                    "Write a status report for the runner fleet with a chart, then plan the next sprint.\n\n@\(photo?.path ?? "/tmp/missing.png")"
                ),
                .toolTodos(
                    id: "td1",
                    items: [
                        TodoItem(text: "Read the runner list", status: .completed),
                        TodoItem(text: "Check backups and the certificate", status: .completed),
                        TodoItem(text: "Write the report", status: .inProgress),
                        TodoItem(text: "Plan the next sprint", status: .pending),
                    ]),
                .toolUse(id: "r1", name: "Read", summary: "docs/runners.md"),
                .toolResult(id: "r1", name: "Read", ok: true, exitCode: nil, output: "84 lines", durationMs: 120),
                .toolUse(id: "b1", name: "Bash", summary: "ainkradctl runners list --json"),
                .toolResult(
                    id: "b1", name: "Bash", ok: true, exitCode: 0,
                    output:
                        "mac-studio  online  2/4\nlinux-01    online  2/2\nhome-server online  1/2\nbuild-box   offline 0/2",
                    durationMs: 900),
                .subAgent(
                    id: "sa1", type: "Explore", task: "Find where queue limits are enforced",
                    prompt: "Search the Core for where a runner's session limit is checked and report the files.",
                    result: nil, ok: nil, durationMs: nil),
                .toolResult(
                    id: "sa1", name: "Task", ok: true, exitCode: nil,
                    output:
                        "Limits are checked in two places:\n- `crates/core/src/sched.rs` — `admit()`\n- `crates/core/src/runner.rs` — `capacity()`",
                    durationMs: 18_400),
                .subAgent(
                    id: "sa2", type: "general-purpose", task: "Draft the restart steps for build-box",
                    prompt: "Write the steps to restart a runner from its host.", result: nil, ok: nil, durationMs: nil),
                .toolUse(id: "w1", name: "WebSearch", summary: "macOS launchd restart service"),
                .toolResult(
                    id: "w1", name: "WebSearch", ok: true, exitCode: nil, output: "5 results", durationMs: 1_400),
                .toolUse(id: "f1", name: "Bash", summary: "ssh build-box uptime"),
                .toolResult(
                    id: "f1", name: "Bash", ok: false, exitCode: 255,
                    output: "ssh: connect to host build-box: timed out",
                    durationMs: 10_000),
                .toolEdit(
                    id: "e1", name: "Edit", path: "docs/runners.md", old: "Restart from the app.",
                    new:
                        "Restart from the app, or on the host:\n  launchctl kickstart -k gui/$(id -u)/io.ainkrad.runner",
                    ok: true, durationMs: 80),
                .toolEdit(
                    id: "e2", name: "Write", path: "reports/fleet-2026-11-15.md", old: "",
                    new: "# Runner fleet status\nThree of four runners are online.", ok: true, durationMs: 40),
                .assistant(report),
                .plan(id: "p1", text: plan),
                .turnEnded(costMicros: 640_000, tokens: 57_200),
            ] + turnTwo + turnThree, endsAt: nil)
    }

    /// Turn 2 (Ahmed, 2026-11-16: "a session that has all possible features"): searches, a fetch, code edits across
    /// several files (real diffs for Review), Code Mode, a failed sub-agent, connection cues that worked and one refused,
    /// and approvals allowed, denied and expired.
    private static var turnTwo: [EntryKind] {
        let schedOld = """
            pub fn admit(&self, s: &Session) -> Admit {
                if self.load() >= self.capacity { return Admit::Queue; }
                Admit::Now
            }
            """
        let schedNew = """
            pub fn admit(&self, s: &Session) -> Admit {
                // One account may hold at most half the runner's slots.
                let mine = self.sessions.iter().filter(|x| x.account == s.account).count();
                if mine * 2 >= self.capacity { return Admit::Queue(Reason::AccountShare); }
                if self.load() >= self.capacity { return Admit::Queue(Reason::Full); }
                Admit::Now
            }
            """
        let queueNew = """
            /// Sessions waiting for a slot, oldest first, at most one turn per account at the front.
            pub struct FairQueue { waiting: VecDeque<SessionId> }

            impl FairQueue {
                pub fn push(&mut self, id: SessionId) { self.waiting.push_back(id); }
                pub fn next(&mut self) -> Option<SessionId> { self.waiting.pop_front() }
            }
            """
        return [
            .user("Good. Now put the account share into the scheduler, add a test, and push a branch."),
            .toolUse(id: "s1", name: "Grep", summary: "fn admit("),
            .toolResult(
                id: "s1", name: "Grep", ok: true, exitCode: nil, output: "3 matches in 2 files", durationMs: 60),
            .toolUse(id: "s2", name: "Glob", summary: "crates/core/src/**/*.rs"),
            .toolResult(id: "s2", name: "Glob", ok: true, exitCode: nil, output: "42 files", durationMs: 30),
            .toolUse(
                id: "w2", name: "WebFetch", summary: "https://docs.rs/tokio/latest/tokio/sync/struct.Semaphore.html"),
            .toolResult(id: "w2", name: "WebFetch", ok: true, exitCode: nil, output: "Fetched 18 KB", durationMs: 820),
            .assistant(
                "The limit is checked only in `admit()`. I'll add the **account share** there and a small `FairQueue` so a waiting session from another account can go first."
            ),
            .toolEdit(
                id: "e3", name: "MultiEdit", path: "crates/core/src/sched.rs", old: schedOld, new: schedNew, ok: true,
                durationMs: 110),
            .toolEdit(
                id: "e4", name: "Write", path: "crates/core/src/queue.rs", old: "", new: queueNew, ok: true,
                durationMs: 50),
            .toolEdit(
                id: "e5", name: "Edit", path: ".github/workflows/ci.yml", old: "timeout-minutes: 20",
                new: "timeout-minutes: 30", ok: false, durationMs: 20),
            .toolUse(id: "c1", name: "ainkrad_search", summary: "queue fairness"),
            .toolResult(
                id: "c1", name: "ainkrad_search", ok: true, exitCode: nil,
                output: "runners.load(), sessions.waiting(), accounts.share()\n[1 call, 40 ms]", durationMs: 40),
            .toolUse(id: "c2", name: "ainkrad_run", summary: "await runners.load()"),
            .toolResult(
                id: "c2", name: "ainkrad_run", ok: true, exitCode: nil,
                output: "{ \"mac-studio\": 0.48, \"linux-01\": 0.91 }\n[3 calls, 120 ms]", durationMs: 120),
            .toolUse(id: "t2", name: "Bash", summary: "cargo test -p ainkrad-core sched"),
            .toolResult(
                id: "t2", name: "Bash", ok: true, exitCode: 0,
                output:
                    "running 14 tests\ntest sched::account_share_queues_the_third ... ok\ntest sched::fair_queue_orders_oldest_first ... ok\ntest result: ok. 14 passed; 0 failed",
                durationMs: 14_300),
            .subAgent(
                id: "sa3", type: "code-reviewer", task: "Review the scheduler change",
                prompt: "Review crates/core/src/sched.rs and queue.rs for races and missing tests.", result: nil,
                ok: nil, durationMs: nil),
            .toolResult(
                id: "sa3", name: "Task", ok: false, exitCode: nil,
                output: "Could not finish: the review timed out after 5 minutes.", durationMs: 300_000),
            .toolUse(id: "g2", name: "github.get_issue", summary: "#188"),
            .toolResult(id: "g2", name: "github.get_issue", ok: true, exitCode: nil, output: "", durationMs: 280),
            .toolUse(id: "j1", name: "jira.create_issue", summary: "Queue fairness"),
            .toolResult(
                id: "j1", name: "jira.create_issue", ok: false, exitCode: nil,
                output: "Jira is not connected for this runner.", durationMs: 150),
            .approvalRequest(
                id: "ap1", tool: "Bash", input: "git push -u origin feat/queue-fairness", timeoutSecs: 300),
            .approvalDecided(id: "ap1", approved: true),
            .approvalRequest(
                id: "ap2", tool: "Edit", input: "Change .github/workflows/ci.yml (timeout 20 → 30 min)",
                timeoutSecs: 300
            ),
            .approvalDecided(id: "ap2", approved: false),
            .approvalRequest(id: "ap3", tool: "WebFetch", input: "https://intranet.example.com/oncall", timeoutSecs: 1),
            .assistant(
                """
                Pushed **feat/queue-fairness**. The CI change was denied, so the timeout stays at 20 minutes.

                - `admit()` now queues a third session from the same account (`Reason::AccountShare`).
                - `FairQueue` hands the next free slot to the oldest waiting session.
                - 14 tests pass, 2 of them new.

                The reviewer timed out; I can run it again with a smaller scope.
                """),
            .turnEnded(costMicros: 1_480_000, tokens: 88_400),
        ]
    }

    /// Turn 3: the runner restarted mid-session and it resumed; the last step waits on your approval.
    private static var turnThree: [EntryKind] {
        [
            .interrupted(reason: "mac-studio restarted"),
            .started(harness: "claude", resumed: true),
            .user("Continue: open the PR against development and tell me what is left."),
            .toolTodos(
                id: "td2",
                items: [
                    TodoItem(text: "Read the runner list", status: .completed),
                    TodoItem(text: "Check backups and the certificate", status: .completed),
                    TodoItem(text: "Write the report", status: .completed),
                    TodoItem(text: "Plan the next sprint", status: .completed),
                    TodoItem(text: "Open the pull request", status: .inProgress),
                ]),
            .assistant("Everything is pushed. Opening the pull request needs your approval."),
            .approvalRequest(
                id: "ap4", tool: "Bash",
                input: "gh pr create --base development --title \"Queue fairness: account share and FairQueue\"",
                timeoutSecs: 600),
        ]
    }

    /// A small picture saved in the caches, so the demo's attachments and inline images have a real file to show.
    private static func demoImage(_ name: String, hue: CGFloat, bars: Bool = false) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = caches.appending(path: "com.ainkrad.core/demo")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "\(name).png")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let size = NSSize(width: 640, height: 400)
        let image = NSImage(size: size, flipped: false) { r in
            NSColor(hue: hue, saturation: 0.25, brightness: 0.35, alpha: 1).setFill()
            r.fill()
            if bars {
                let values: [CGFloat] = [0.35, 0.5, 0.42, 0.7, 0.62, 0.88, 0.55]
                let w = r.width / CGFloat(values.count * 2)
                for (i, v) in values.enumerated() {
                    NSColor(hue: hue, saturation: 0.45, brightness: 0.8, alpha: 1).setFill()
                    NSBezierPath(
                        roundedRect: NSRect(
                            x: w * 0.5 + CGFloat(i) * w * 2, y: 30, width: w, height: (r.height - 60) * v),
                        xRadius: 6, yRadius: 6
                    ).fill()
                }
            } else {
                NSColor(hue: hue, saturation: 0.3, brightness: 0.7, alpha: 1).setFill()
                NSBezierPath(roundedRect: r.insetBy(dx: 60, dy: 60), xRadius: 16, yRadius: 16).fill()
            }
            return true
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else { return nil }
        try? png.write(to: url)
        return url
    }
}
#endif
