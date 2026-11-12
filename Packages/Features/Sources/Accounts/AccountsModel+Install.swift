import Admin
import CoreKit
import Foundation

/// An install of a tool on a runner, as the Core reports it.
struct ToolProgress: Equatable, Sendable {
    enum State: String, Sendable { case running, done, failed }
    var state: State
    var percent: Int
    var step: String
    var reason: String?
}

/// The words for a Claude plan check (`POST /accounts/{id}/check`). It uses a little of the plan's quota, never money.
enum PlanCheckWords {
    static func of(_ r: String) -> (title: String, line: String, ok: Bool) {
        switch r {
        case "ok":
            ("Signed in and working", "A test message went through a runner. It used a little of your plan.", true)
        case "token_expired": ("Sign-in expired", "Claude no longer accepts this sign-in. Sign in again.", false)
        case "limit_reached":
            (
                "Plan limit reached", "You have used all of this plan for now. It works again when the limit resets.",
                false
            )
        case "no_runner": ("No runner can check it", "Add a runner that has Claude installed, then check again.", false)
        case "runner_outdated": ("Runner is out of date", "Update the runner, then check again.", false)
        case "runner_busy": ("Runner is busy", "Every runner is working at its limit. Try again in a minute.", false)
        case "egress_not_proven":
            ("Runner cannot be trusted yet", "The runner could not prove it limits where AI sessions connect.", false)
        case "unreachable":
            ("Could not reach Claude", "The runner could not connect to Claude. Check its internet connection.", false)
        case "timeout": ("Claude did not answer", "The check took too long. Try again.", false)
        default: ("The check failed", "Something went wrong while checking. Try again.", false)
        }
    }
}

extension AccountsModel {
    func checkPlan(_ a: AccountItem) async {
        guard let service, checking == nil, mayWrite() else { return }
        checking = a.id
        checkNote[a.id] = nil
        defer { checking = nil }
        do {
            planChecks[a.id] = (try await service.check(account: a.id), Date())
        } catch {
            checkNote[a.id] = words(error)
        }
    }

    /// One `runner.tool_install` event.
    public func toolInstall(_ f: [String: String]) {
        guard let runner = f["runner"], let tool = f["tool"], let state = f["state"].flatMap(ToolProgress.State.init)
        else { return }
        installs["\(runner)|\(tool)"] = ToolProgress(
            state: state, percent: Int(f["percent"] ?? "") ?? 0, step: f["step"] ?? "", reason: f["reason"])
    }

    /// Tools the Core can install for a provider's harness.
    static let installable: Set<String> = ["claude", "codex"]

    /// The runner an install would go to: an online one without the tool yet, else any online one.
    func installTarget(_ p: ProviderItem, _ runners: [AccountRunner]) -> AccountRunner? {
        let online = runners.filter(\.online)
        return online.first { $0.tools[p.harness] == nil } ?? online.first
    }

    func install(_ p: ProviderItem, on r: AccountRunner) async {
        guard let service, mayWrite() else { return }
        let key = "\(r.id)|\(p.harness)"
        installs[key] = ToolProgress(state: .running, percent: 0, step: "Starting…")
        do {
            if r.tools[p.harness] == nil {
                try await host.elevated(
                    "Install \(ProviderWords.title(p)) on \(r.name)", done: "started", keepsEdit: true
                ) { try await service.installTool(runner: r.id, tool: p.harness) }
            } else {
                installs[key] = ToolProgress(state: .done, percent: 100, step: "")
            }
        } catch is AdminDeclined {
            installs[key] = nil
        } catch {
            installs[key] = ToolProgress(state: .failed, percent: 0, step: "", reason: words(error))
        }
    }

    /// After the tool is there, a runner that still offers no AI sessions gets them turned on (one more Touch ID).
    func enableAgentsIfOff(_ r: AccountRunner) async -> String? {
        guard let service, r.policy?.agents != true else { return nil }
        do {
            try await host.elevated("Turn on AI sessions on \(r.name)", done: "changed", keepsEdit: true) {
                try await service.enableAgents(runner: r.id, policy: r.policy)
            }
            return nil
        } catch is AdminDeclined {
            return "AI sessions are still off on \(r.name)."
        } catch {
            return words(error)
        }
    }
}
