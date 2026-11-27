#if DEBUG
import Foundation

/// Debug only: the Runs page's configurations, environments, variables and runs on made-up data (two configurations beside the
/// Default). Writes change nothing; nothing reaches a Core.
final class DemoConfigsService: RunConfigsService, @unchecked Sendable {
    private let items = [
        RunConfigItem(
            id: 1, name: "Admin dev server", command: "npm run dev", workdir: "./lanterna-admin", runner: "automatic",
            port: 3000, restart: true),
        RunConfigItem(
            id: 2, name: "Queue worker", command: "php artisan queue:work", workdir: "./lanterna-api",
            runner: "automatic", port: nil, restart: false),
    ]

    func configs(project: Int64) async throws -> [RunConfigItem] { items }
    func createConfig(project: Int64, name: String, command: String) async throws -> RunConfigItem { items[0] }
    func updateConfig(project: Int64, id: Int64, _ patch: RunConfigPatch) async throws -> RunConfigItem { items[0] }
    func deleteConfig(project: Int64, id: Int64) async throws {}
    func duplicateConfig(project: Int64, id: Int64) async throws -> RunConfigItem { items[0] }
    func start(project: Int64, config: Int64, environment: String?, replace: Bool) async throws -> RunRecord {
        Self.record("r_new", "starting", config, minutes: 0)
    }
    func environments(project: Int64) async throws -> [String] { ["Development", "Staging"] }
    func addEnvironment(project: Int64, name: String) async throws -> [String] { ["Development", "Staging", name] }
    func deleteEnvironment(project: Int64, name: String) async throws -> [String] { ["Development", "Staging"] }
    func vars(project: Int64, config: Int64, env: String) async throws -> [RunVarItem] {
        env == "Staging"
            ? [RunVarItem(key: "API_URL", secret: nil, size: 25)]
            : [
                RunVarItem(key: "API_URL", secret: nil, size: 22), RunVarItem(key: "FEATURE_FLAGS", secret: nil, size: 14),
                RunVarItem(key: "DATABASE_URL", secret: "db_password", size: 0),
            ]
    }
    func setVar(project: Int64, config: Int64, env: String, key: String, value: String?, secret: String?) async throws {}
    func deleteVar(project: Int64, config: Int64, env: String, key: String) async throws {}
    func reveal(project: Int64, config: Int64, env: String, key: String) async throws -> String { "" }
    func importEnv(project: Int64, config: Int64, env: String, text: String) async throws -> EnvImport {
        EnvImport(imported: 0, skipped: 0)
    }
    func diff(project: Int64, config: Int64, a: String, b: String) async throws -> [EnvDiffItem] { [] }
    func runners() async throws -> [RunnerOption] { [RunnerOption(id: "core-oracle", name: "core-oracle")] }

    private static func record(
        _ id: String, _ state: String, _ config: Int64?, minutes: Double, error: String? = nil, why: String? = nil
    ) -> RunRecord {
        RunRecord(
            id: id, state: state, configID: config, environment: config == nil ? nil : "Development", runner: "core-oracle",
            startedAt: Date().addingTimeInterval(-minutes * 60),
            stoppedAt: ["stopped", "failed"].contains(state) ? Date().addingTimeInterval(-minutes * 60 + 90) : nil,
            stopReason: why, error: error)
    }

    func history(project: Int64) async throws -> [RunRecord] {
        switch project {
        case 1:
            [
                Self.record("r_1", "running", nil, minutes: 120), Self.record("r_2", "running", 1, minutes: 40),
                Self.record("r_3", "stopped", 2, minutes: 1_500, why: "user"),
                Self.record("r_4", "failed", 2, minutes: 2_900, error: "queue: exited with code 1"),
            ]
        case 2: [Self.record("r_5", "stopped", nil, minutes: 1_500, why: "user")]
        case 3: [Self.record("r_6", "failed", nil, minutes: 20, error: "web: npm ci exited with code 1")]
        default: [Self.record("r_7", "stopped", nil, minutes: 4_000, why: "idle")]
        }
    }
}

/// A run's log lines on made-up data: the same few lines for every run.
struct DemoLogSource: RunLogSource {
    func page(after: Int, service: String?) async throws -> RunLogPage {
        guard after == 0 else { return RunLogPage(next: after) }
        let lines = [
            ("web", "ready on http://localhost:3000"), ("api", "listening on :8000"),
            ("api", "GET /health 200 3 ms"), ("queue", "worker started, 2 jobs waiting"),
            ("web", "GET /products 200 41 ms"), ("api", "GET /api/products 200 18 ms"),
            ("queue", "processed SendReceipt in 120 ms"), ("web", "GET /cart 200 36 ms"),
        ].filter { service == nil || $0.0 == service }
        let now = Date()
        return RunLogPage(
            lines: lines.enumerated().map {
                ProjectLive.LogLine(
                    service: $0.element.0, text: $0.element.1, seq: $0.offset + 1,
                    at: now.addingTimeInterval(Double($0.offset - lines.count) * 7))
            }, next: lines.count)
    }
}
#endif
