#if DEBUG
import Foundation

/// Debug only: what each demo project says of itself by kind and name, so a shot of an app, an infra stack or a book never
/// shows a web shop's log lines, failure or sessions, and no two repos share commits. Applied to the finished sample list.
enum DemoData {
    typealias Line = (service: String, text: String)

    static func kinds(_ p: ProjectItem) -> [ProjectKind] {
        if !p.kinds.isEmpty { return p.kinds }
        return [p.kindName.flatMap(ProjectKind.init(rawValue:)) ?? .web]
    }

    /// The default web failure the stand-in writes; a scene that wrote its own words keeps them.
    static let webFailure = "api stopped 40 s after start."

    // MARK: Logs

    static func logs(_ k: [ProjectKind], failed: Bool) -> [Line] {
        if k.contains(.web) {
            return failed
                ? [
                    ("mysql", "ready for connections · 8.4.2"), ("web", "Next.js 15.1 · ready in 2.1 s"),
                    ("api", "Missing environment variable STRIPE_SECRET"), ("api", "exited with code 1"),
                ]
                : [
                    ("mysql", "ready for connections · 8.4.2"), ("api", "Server running on 0.0.0.0:8000"),
                    ("web", "Next.js 15.1 · ready in 2.1 s"), ("web", "GET / 200 in 84 ms"),
                    ("api", "GET /api/products?page=1 200 31 ms"), ("queue", "ResizeImage ........ 212 ms DONE"),
                ]
        }
        if k.contains(.app) {
            return failed
                ? [
                    ("xcodebuild", "Resolve Package Graph"), ("xcodebuild", "CompileSwift normal arm64 CourierMap.swift"),
                    ("xcodebuild", "error: no such module ‘Tidepool’"), ("xcodebuild", "** BUILD FAILED **"),
                ]
                : [
                    ("xcodebuild", "Resolve Package Graph"), ("xcodebuild", "CompileSwift normal arm64 CourierMap.swift"),
                    ("xcodebuild", "Linking Tidepool"), ("xcodebuild", "** BUILD SUCCEEDED ** · 41 s"),
                    ("simctl", "Installing Tidepool.app on iPhone 16"), ("gradle", "BUILD SUCCESSFUL in 1m 12s"),
                ]
        }
        if k.contains(.infra) {
            return failed
                ? [
                    ("vault", "systemd[1]: Started vault.service"), ("network", "container network: healthy"),
                    ("gateway", "bind 0.0.0.0:443: address already in use"),
                    ("gateway", "gateway.service: Main process exited, status=1/FAILURE"),
                ]
                : [
                    ("network", "container network: healthy"), ("vault", "systemd[1]: Started vault.service"),
                    ("db", "database system is ready to accept connections"),
                    ("queue", "container queue: health check passed"), ("gateway", "listening on :443"),
                    ("gateway", "upstream db: ok"),
                ]
        }
        return []
    }

    static func failure(_ k: [ProjectKind]) -> (String, String)? {
        if k.contains(.web) { return nil }
        if k.contains(.app) {
            return ("The last build failed.", "Read the log, fix what stops the build, then build it again.")
        }
        if k.contains(.infra) {
            return (
                "The gateway stopped 40 s after start.",
                "Port 443 is taken. Free it or change the gateway port in Run setup, then start again."
            )
        }
        return nil
    }

    // MARK: Sessions

    private static func s(
        _ t: String, _ st: ProjectLive.Session.State, _ h: String, _ w: String, _ b: String, _ c: String
    ) -> ProjectLive.Session {
        .init(title: t, state: st, harness: h, when: w, runner: "core-oracle", branch: b, cost: c)
    }

    static func sessions(_ p: ProjectItem, _ k: [ProjectKind]) -> [ProjectLive.Session]? {
        if k.contains(.web), p.id == 1 { return nil }
        if k.contains(.web) {
            switch p.id {
            case 2:
                return [
                    s("Reconcile February ledger imports", .needsYou, "Claude Code", "9 m", "fix/ledger-import", "$0.31"),
                    s("Add a VAT export to Reports", .running, "Codex", "48 m", "feat/vat-export", "$0.87"),
                ]
            case 3:
                return [
                    s("Autosave drafts every 10 seconds", .done, "Claude Code", "26 m", "feat/autosave", "$0.52"),
                    s("Fix the comment thread order", .done, "Codex", "1 h 5 m", "fix/thread-order", "$0.22"),
                    s("Template picker keyboard support", .running, "Claude Code", "7 m", "feat/picker-keys", "$0.15"),
                ]
            default:
                return [
                    s("Merge duplicate contacts", .running, "Claude Code", "18 m", "feat/merge-contacts", "$0.40"),
                    s("Import deals from CSV", .done, "Codex", "2 h", "feat/csv-deals", "$0.95"),
                ]
            }
        }
        if k.contains(.app) {
            return [
                s("Fix the courier map crash on iOS 18", .needsYou, "Claude Code", "11 m", "fix/map-crash", "$0.36"),
                s("Cache the order list for offline use", .running, "Codex", "55 m", "feat/offline-orders", "$0.78"),
                s("Move the Android build to Gradle 8.10", .done, "Claude Code", "34 m", "chore/gradle-8", "$0.29"),
            ]
        }
        if k.contains(.infra) {
            return [
                s("Rotate the vault tokens", .needsYou, "Claude Code", "6 m", "ops/rotate-vault", "$0.19"),
                s("Add a second gateway node", .running, "Codex", "1 h 20 m", "feat/gateway-2", "$1.02"),
            ]
        }
        return [
            s("Outline chapter 4: the storm", .running, "Claude Code", "22 m", "main", "$0.27"),
            s("Check the tide tables against the notes", .done, "Codex", "1 h", "main", "$0.12"),
        ]
    }

    // MARK: Commits per repo

    private static func c(_ t: String, _ by: String, _ h: String) -> ProjectLive.Commit {
        .init(title: t, by: by, hash: h)
    }

    static func commits(_ repo: RepoItem) -> [ProjectLive.Commit] {
        let h = repo.head ?? "3d9b7e1"
        let n = repo.name
        if n.hasSuffix("admin") {
            return [
                c("Show refunds in the order table", "Omar K. · 3 h", h), c("Add a stock filter to Products", "Lina M. · yesterday", "b04c8e2"),
                c("Fix the date picker in Reports", "Omar K. · Mon", "2fd61a9"), c("Hide archived users", "Lina M. · Sun", "c7710ab"),
            ]
        }
        if n.hasSuffix("web") {
            return [
                c("Lazy-load product images", "Lina M. · 4 m", h), c("Add EU VAT rates for 2027", "AI session · 2 h", "a81f03d"),
                c("Tighten the cart empty state", "Omar K. · yesterday", "5c2e7b0"), c("Fix the footer on small screens", "Lina M. · Mon", "e09d1aa"),
            ]
        }
        if n.hasSuffix("api") {
            return [
                c("Round coupon totals per line, not per order", "Lina M. · 4 m", h),
                c("Cache product images for 1 day", "Omar K. · yesterday", "5c2e7b0"),
                c("Fix stock count after refunds", "Lina M. · Mon", "e09d1aa"), c("Upgrade Laravel to 11.31", "Omar K. · Sun", "77b3c12"),
            ]
        }
        if n.hasSuffix("ios") {
            return [
                c("Cluster courier pins on the map", "Sam R. · 20 m", h), c("Fix the sign-in keyboard overlap", "Dana P. · yesterday", "6e21d0c"),
                c("Bump the deployment target to iOS 17", "Sam R. · Mon", "90aa3f1"),
            ]
        }
        if n.hasSuffix("android") {
            return [
                c("Move to Gradle 8.10", "AI session · 34 m", h), c("Handle the Back gesture on the order screen", "Dana P. · 2 d", "1b8cd47"),
                c("Update Compose to 1.7", "Sam R. · Fri", "f4402ce"),
            ]
        }
        if n.hasSuffix("infra") {
            return [
                c("Add a second gateway node", "AI session · 1 h", h), c("Pin the vault image to 1.18", "Mia T. · yesterday", "0c97a35"),
                c("Open port 8443 for the queue", "Mia T. · Tue", "d83e6b2"),
            ]
        }
        if n.hasSuffix("os") {
            return [
                c("Harden the SSH settings", "Mia T. · 3 h", h), c("Enable unattended security updates", "Jon B. · Mon", "7a5f1e0"),
            ]
        }
        return [
            c("Tidy the README", "Ana V. · 1 h", h), c("Update the dependency list", "Ana V. · Mon", "8e3b6d4"),
        ]
    }

    // MARK: Apply

    /// The name a project's code goes by ("Lanterna", "Tidepool"): the module an app build cannot find.
    static func module(_ p: ProjectItem) -> String { String(p.name.split(separator: " ").first ?? "App") }

    /// A failed start names the step that broke; the log shows that step's own lines, never another failure's.
    static func failedStepLogs(_ p: ProjectItem, _ live: ProjectLive) -> [Line]? {
        guard let d = live.steps.first(where: { $0.state == .failed })?.detail else { return nil }
        let m = module(p)
        if d.contains("npm ci") {
            return [
                ("web", "> npm ci"), ("web", "npm ERR! code EUSAGE"),
                ("web", "npm ERR! `npm ci` can only install with an existing package-lock.json"),
                ("web", "npm ERR! A complete log of this run can be found in the npm cache"),
                ("web", "npm ci exited with code 1"),
            ]
        }
        if d.contains("no such module") {
            return [
                ("xcodebuild", "Resolve Package Graph"),
                ("xcodebuild", "CompileSwift normal arm64 \(m == "Tidepool" ? "CourierMap" : "LampList").swift"),
                ("xcodebuild", "error: no such module ‘\(m)’"), ("xcodebuild", "** BUILD FAILED **"),
            ]
        }
        return nil
    }

    static func adapt(_ p: inout ProjectItem) {
        p.slug = ProjectRules.slug(from: p.name)
        guard var live = p.live else { return }
        let k = kinds(p)
        let failed = p.run?.state == .failed
        if !live.logs.isEmpty {
            let t = Date()
            let lines = (failed ? failedStepLogs(p, live) : nil) ?? logs(k, failed: failed)
            live.logs = lines.enumerated().map {
                .init(
                    service: $0.element.service, text: $0.element.text,
                    at: failed ? nil : t.addingTimeInterval(Double($0.offset - lines.count) * 10))
            }
        }
        if failed, live.failure == webFailure, let (words, fix) = failure(k) {
            live.failure = words
            live.failureFix = fix
        }
        if !live.sessions.isEmpty, let own = sessions(p, k) { live.sessions = own }
        live.repoExtras = Dictionary(
            uniqueKeysWithValues: p.repos.map { r in
                let size = ["48 MB", "112 MB", "9 MB", "230 MB"][abs(r.name.hashValue % 4)]
                return (
                    r.name,
                    ProjectLive.RepoExtra(
                        usedBy: r.primary ? "2 AI sessions · the run" : "1 AI session", size: size, commits: commits(r))
                )
            })
        if k.contains(.infra), !k.contains(.web), !live.services.isEmpty {
            let names = ["network", "vault", "queue", "db", "gateway"]
            live.services = live.services.enumerated().map { i, v in
                let st: ProjectLive.Service.State = failed ? (i == 4 ? .exited : .up) : v.state
                return .init(name: names[i % 5], memory: v.memory, state: st, cpu: v.cpu, restarts: failed && i == 4 ? 3 : 0)
            }
        }
        p.live = live
    }

    /// The log lines the stand-in Core serves for a project's run (the Overview island and the Logs page).
    static func source(_ p: ProjectItem?) -> [Line] {
        guard let p else { return logs([.web], failed: false) }
        let failed = p.run?.state == .failed
        return (failed ? p.live.flatMap { failedStepLogs(p, $0) } : nil) ?? logs(kinds(p), failed: failed)
    }
}
#endif
