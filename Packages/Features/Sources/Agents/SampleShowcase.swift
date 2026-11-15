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
            usage: AgentUsageInfo(input: 48_000, output: 9_200, costMicros: 640_000), index: 20)
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
            ], endsAt: nil)
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
