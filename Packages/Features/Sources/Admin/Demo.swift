#if DEBUG
import CoreKit
import Foundation
import Shell

/// Debug only: every admin state of the prototype on sample data and a stand-in service, for screenshots and for the reviewer
/// to click through. Nothing here reaches a Core. Names and values follow the prototype's `admin-data.js`, shaped like the API's.
@MainActor
public final class AdminDemo {
    final class Service: AdminService, @unchecked Sendable {
        var settingList: [SettingItem] = DemoData.settings
        var auditRows: [AuditItem] = DemoData.audit
        func settings() async throws -> [SettingItem] { settingList }
        func setSetting(_ key: String, _ value: Int64) async throws -> SettingItem {
            guard let i = settingList.firstIndex(where: { $0.key == key }) else { throw CoreError.offline("gone") }
            settingList[i].value = value
            settingList[i].source = "server"
            return settingList[i]
        }
        func resetSetting(_ key: String) async throws -> SettingItem {
            guard let i = settingList.firstIndex(where: { $0.key == key }) else { throw CoreError.offline("gone") }
            settingList[i].value = settingList[i].defaultValue
            settingList[i].source = nil
            return settingList[i]
        }
        func history(_ key: String) async throws -> [SettingChangeItem] { DemoData.history[key] ?? [] }
        func secrets() async throws -> [SecretItem] { DemoData.secrets }
        func createSecret(_ draft: SecretDraft) async throws -> SecretItem { DemoData.secrets[0] }
        func rotateSecret(_ name: String, value: String, fileName: String?) async throws -> SecretItem {
            DemoData.secrets[0]
        }
        func secretGroups() async throws -> [SecretGroupItem] { DemoData.groups }
        func createSecretGroup(name: String, description: String, runners: [String]) async throws -> SecretGroupItem {
            SecretGroupItem(name: name, description: description, members: [], runners: runners)
        }
        func updateSecretGroup(_ name: String, description: String, runners: [String]) async throws -> SecretGroupItem {
            SecretGroupItem(name: name, description: description, members: [], runners: runners)
        }
        func deleteSecretGroup(_ name: String) async throws {}
        func leaseGroup(_ name: String, runner: String, ttl: Int64?) async throws -> [LeaseItem] {
            [
                LeaseItem(
                    lease: "l_8Kd2Qx", secret: "aws-access-key", runner: runner,
                    expiresAt: Date().addingTimeInterval(120))
            ]
        }
        func deleteSecret(_ name: String) async throws {}
        func lease(_ name: String, runner: String, ttl: Int64?) async throws -> LeaseItem {
            LeaseItem(lease: "l_8Kd2Qx", secret: name, runner: runner, expiresAt: Date().addingTimeInterval(120))
        }
        func runners() async throws -> [RunnerChoice] { DemoData.runners }
        func audit(before: Int64?, limit: Int, filter: AuditFilter) async throws -> AuditPageItem {
            let rows = auditRows.filter {
                (filter.kind.isEmpty || $0.action.hasPrefix(filter.kind))
                    && (filter.target.isEmpty || "\($0.entityKind ?? ""):\($0.entityRef ?? "")".contains(filter.target))
                    && (filter.actor == .any || $0.actor.kind == filter.actor.rawValue)
                    && (!filter.nobodyWatching || ($0.origin.map { !$0.watched } ?? false))
                    && (before == nil || $0.seq < before!)
            }
            let page = Array(rows.prefix(limit))
            return AuditPageItem(items: page, nextBefore: rows.count > limit ? page.last?.seq : nil)
        }
        func metrics() async throws -> String { DemoData.metricsText }
    }

    public static let scenes = [
        "settings", "settings-switching", "settings-editing", "settings-refused", "settings-history", "switches",
        "secrets", "secrets-new",
        "secrets-lease", "secrets-touchid-cancelled", "audit", "audit-selected", "audit-nomatch", "audit-connections",
        "audit-connection-history", "audit-accounts",
        "audit-agents", "audit-code-mode", "audit-code-mode-nobody", "settings-code-mode", "switches-code-mode",
        "audit-nobody", "audit-one", "audit-many", "ops",
        "state-loading",
        "state-empty", "state-error", "state-scope", "banner-resuming", "banner-rate", "banner-renewing",
        "banner-restarted",
    ]

    private let admin: AdminModel
    private let service = Service()
    private let setNotice: @MainActor (AdminNotice?) -> Void

    /// `setNotice` puts a step-up outcome where the panels show it (the app owns it).
    public init(admin: AdminModel, setNotice: @escaping @MainActor (AdminNotice?) -> Void) {
        self.admin = admin
        self.setNotice = setNotice
    }

    private var shell: ShellModel { admin.host.shell }

    private func open(_ section: String) async {
        shell.dialog = nil
        shell.settings.selected = section
        shell.open(.settings)
        try? await Task.sleep(for: .milliseconds(700))  // the section loads itself when it appears
    }

    public func show(_ scene: String) async {
        shell.linkNotice = nil
        shell.coreLink = .live
        setNotice(nil)
        admin.use(service)
        admin.registry.clearUI()
        admin.audit.clearFilters()
        admin.audit.selected = nil
        service.auditRows = DemoData.audit
        admin.ops.showRaw = false
        try? await Task.sleep(for: .milliseconds(300))
        let first = DemoData.settings[0]
        switch scene {
        case "settings": await open("core")
        case "settings-switching":
            await open("core")
            let wait = DemoData.settings.first { $0.key == "scheduler.wait_max_secs" } ?? first
            try? await Task.sleep(for: .milliseconds(600))
            admin.registry.cursor = wait.key
            try? await Task.sleep(for: .milliseconds(900))  // the list scrolls to it first
            admin.registry.beginEdit(wait)
            admin.registry.draft = "900"
        case "settings-editing":
            await open("core")
            admin.registry.beginEdit(first)
            admin.registry.draft = "2400"
        case "settings-refused":
            await open("core")
            admin.registry.beginEdit(first)
            admin.registry.draft = "70000"
            await admin.registry.saveEdit(first)
        case "settings-history":
            await open("core")
            await admin.registry.toggleHistory(first.key)
        case "switches": await open("switches")
        case "secrets", "secrets-new", "secrets-lease", "secrets-touchid-cancelled":
            await open("secrets")
            if scene == "secrets-new" { SecretDialogs.openNew(admin) }
            if scene == "secrets-lease" { SecretDialogs.openLease(admin, DemoData.secrets[0]) }
            if scene == "secrets-touchid-cancelled" {
                SecretDialogs.openNew(admin)
                setNotice(
                    AdminNotice(
                        title: "Cancelled, nothing was stored.",
                        detail: "Your edit is still here. Try again when you are ready.",
                        symbol: "hand.raised", warn: false))
            }
        case "audit", "audit-selected", "audit-nomatch":
            await open("audit")
            if scene == "audit-selected" { admin.audit.selected = DemoData.audit[2].seq }
            if scene == "audit-nomatch" {
                admin.audit.filter.kind = "terminal."
                try? await Task.sleep(for: .milliseconds(900))
            }
        case "audit-connections", "audit-accounts", "audit-agents":
            await open("audit")
            admin.audit.filter.kind =
                scene == "audit-connections" ? "connection." : scene == "audit-agents" ? "agent." : "account."
            try? await Task.sleep(for: .milliseconds(900))
            admin.audit.selected = admin.audit.items.first?.seq
        case "audit-connection-history":
            // What a connection card's History does: Audit opens already filtered to that connection.
            shell.settings.open("audit", handoff: ["audit.kind": "connection.", "audit.target": "connection:2"])
            shell.open(.settings)
            try? await Task.sleep(for: .milliseconds(1200))
        case "audit-code-mode", "audit-code-mode-nobody":
            service.auditRows = DemoData.codeModeAudit + DemoData.audit
            admin.audit.reset()
            await open("audit")
            admin.audit.filter.kind = CodeModeAudit.areaPrefix
            admin.audit.filter.nobodyWatching = scene == "audit-code-mode-nobody"
            await admin.audit.reload()
            admin.audit.selected = admin.audit.items.first?.seq
            admin.audit.selected = admin.audit.items.dropFirst(2).first?.seq
        case "settings-code-mode":
            await open("core")
            admin.registry.cursor = "code_mode.calls_per_min"
        case "switches-code-mode": await open("switches")
        case "audit-nobody":
            await open("audit")
            admin.audit.filter.nobodyWatching = true
            await admin.audit.reload()
            admin.audit.selected = admin.audit.items.first?.seq
        case "audit-one", "audit-many":
            service.auditRows = scene == "audit-one" ? [DemoData.audit[0]] : DemoData.audit(1_000)
            admin.audit.reset()
            await open("audit")
            await admin.audit.reload()  // the section may already be on screen, so its own load does not run again
            if scene == "audit-many" {
                for _ in 0..<19 { await admin.audit.loadOlder() }
            }
        case "ops":
            await open("ops")
            admin.ops.debugSeedHistory()
        case "state-loading":
            await open("core")
            admin.registry.state = .loading
        case "state-empty":
            await open("audit")
            admin.audit.state = .empty
        case "state-error":
            await open("core")
            admin.registry.state = .failed(
                code: "internal", message: "Something went wrong on the Core.", errorID: "err_8f21c9a4e7b3")
        case "state-scope":
            await open("core")
            admin.registry.state = .forbidden
        case "banner-resuming":
            await open("core")
            shell.coreLink = .reconnecting
        case "banner-rate":
            await open("core")
            shell.linkNotice = .rateLimited(until: Date().addingTimeInterval(24))
        case "banner-renewing":
            await open("core")
            shell.linkNotice = .renewing
        case "banner-restarted":
            await open("core")
            shell.linkNotice = .restarted
        default: await open("core")
        }
    }
}

nonisolated enum DemoData {
    nonisolated static func s(
        _ key: String, _ value: Int64, _ def: Int64, _ min: Int64, _ max: Int64, _ unit: String, _ detail: String
    ) -> SettingItem {
        SettingItem(
            key: key, detail: detail, unit: unit, defaultValue: def, min: min, max: max, value: value,
            source: value == def ? nil : "server")
    }

    nonisolated static let settings: [SettingItem] = [
        s(
            "api.requests_per_min", 1200, 1200, 60, 60_000, "per_minute",
            "Client API requests one device may send per minute, sustained; read at start."),
        s(
            "api.request_burst", 120, 120, 10, 10_000, "count",
            "Client API requests one device may send at once; read at start."),
        s(
            "auth.step_up_secs", 300, 300, 60, 900, "seconds",
            "How long a step-up keeps its session elevated for destructive routes."),
        s(
            "auth.web_session_secs", 28_800, 28_800, 3_600, 86_400, "seconds",
            "How long a web session from a passkey sign-in lives, absolute."),
        s("auth.passkey_admin", 0, 0, 0, 1, "count", "1 lets a passkey hold the admin scope, 0 refuses it."),
        s("code_mode.calls_per_min", 300, 300, 1, 6_000, "per_minute", "Code Mode: operations per minute."),
        s("code_mode.max_run_calls", 100, 100, 1, 1_000, "count", "Code Mode: operations per script."),
        s("code_mode.run_secs", 60, 60, 1, 110, "seconds", "Code Mode: wall time of one script."),
        s("code_mode.call_secs", 30, 30, 1, 110, "seconds", "Code Mode: longest one operation may take."),
        s("code_mode.concurrent", 4, 4, 1, 16, "count", "Code Mode: operations at once."),
        s("code_mode.max_args_bytes", 65_536, 65_536, 256, 393_216, "bytes", "Code Mode: largest request."),
        s("code_mode.max_result_bytes", 200_000, 200_000, 1_024, 250_000, "bytes", "Code Mode: largest answer."),
        s("code_mode.approval_secs", 100, 100, 1, 110, "seconds", "Code Mode: time to answer a risky operation."),
        s("code_mode.idempotency_secs", 600, 600, 10, 86_400, "seconds", "Code Mode: how long a write is remembered."),
        s("code_mode.hide_connection_tools", 0, 0, 0, 1, "count", "Hides the old connection tools for Code Mode."),
        s("secrets.mode", 1, 0, 0, 2, "count", "The secrets broker and gate G-SEC: 0 off, 1 throwaway only, 2 real."),
        s("secrets.provider_accounts", 0, 0, 0, 1, "count", "The narrow gate for AI provider accounts."),
        s("secrets.lease_secs", 120, 120, 10, 900, "seconds", "The longest lifetime of a secret lease."),
        s(
            "terminal.idle_secs", 86_400, 86_400, 0, 2_592_000, "seconds",
            "How long a terminal with no client attached is kept."),
        s(
            "alarm.backup_max_age_secs", 172_800, 172_800, 3_600, 31_536_000, "seconds",
            "The backup_age alarm raises when the newest backup is older than this."),
        s(
            "alarm.cert_min_days", 14, 14, 1, 90, "count",
            "The cert_expiry alarm raises with fewer than this many days left."),
        s(
            "alarm.disk_min_free_pct", 10, 10, 1, 90, "percent",
            "The disk_free alarm raises when less than this share is free."),
        s(
            "scheduler.wait_max_secs", 600, 600, 0, 86_400, "seconds",
            "The longest a chain session waits for an account."),
        s("scheduler.max_hops", 3, 3, 0, 20, "count", "Most failovers one run may make; 0 turns failover off."),
        s("scheduler.failovers_per_10min", 10, 10, 1, 1_000, "count", "Most failovers per user in 10 minutes."),
        s(
            "scheduler.quota_cooldown_secs", 3_600, 3_600, 60, 86_400, "seconds",
            "How long an account rests after its quota runs out."),
    ].enumerated().map { i, item in
        var x = item
        if i == 0 {
            x.value = 600
            x.source = "server"
        }
        if i == 2 { x.value = 300 }
        return x
    }

    nonisolated static let history: [String: [SettingChangeItem]] = [
        "api.requests_per_min": [
            SettingChangeItem(seq: 5_190, at: Date().addingTimeInterval(-86_400), actor: .user(1), old: 1200, new: 600),
            SettingChangeItem(
                seq: 4_120, at: Date().addingTimeInterval(-9 * 86_400), actor: .user(1), old: nil, new: 1200),
        ]
    ]

    nonisolated static let runners = [
        RunnerChoice(id: "d_run2Gt4", name: "mac-studio", online: true, drivers: ["pty", "agent", "exec"]),
        RunnerChoice(id: "d_run9Lq1", name: "linux-01", online: true, drivers: ["pty", "agent"]),
        RunnerChoice(id: "d_run4Zp7", name: "build-box", online: false, drivers: ["agent"]),
    ]

    nonisolated static var secrets: [SecretItem] {
        func make(_ n: String, _ size: Int64, _ ver: Int64, _ del: String, _ r: [String], kind: String = "text")
            -> SecretItem
        {
            var s = SecretItem(
                name: n, owner: "d_mac7Qa2", runners: r, delivery: del, version: ver, size: size, keyID: "k_2026_10",
                createdAt: Date().addingTimeInterval(-5 * 86_400), updatedAt: Date().addingTimeInterval(-3_600 * 5))
            s.kind = kind
            s.lastUsedAt = Date().addingTimeInterval(-7_200)
            s.useCount = 12
            return s
        }
        return [
            make("github-token-test", 40, 3, "env", ["d_run2Gt4", "d_run9Lq1"]),
            make("npm-auth-throwaway", 52, 1, "file", ["d_run9Lq1"], kind: "file"),
            make("git-askpass-test", 36, 2, "askpass", ["d_run2Gt4"]),
        ]
    }

    nonisolated static let groups = [
        SecretGroupItem(
            name: "aws-production", description: "Keys for the production account", members: [], runners: ["d_run9Lq1"])
    ]

    nonisolated static var audit: [AuditItem] { audit(60) }

    /// What AI sessions did through Code Mode and in the Brain, newest first, over the ordinary rows. Made-up names.
    nonisolated static var codeModeAudit: [AuditItem] {
        let project = "customer-portal"
        let phone = AuditOrigin(
            kind: "ai_session", reference: "as_01JC4X7Q3MZ8", rootKind: "person", rootReference: "d_ph18x3Kz")
        func row(_ i: Int, _ action: String, _ json: String) -> AuditItem {
            AuditItem(
                seq: Int64(9_000 - i), at: Date().addingTimeInterval(-Double(i) * 190 - 60), action: action,
                actor: .user(1), entityKind: nil, entityRef: nil, details: json, origin: phone)
        }
        func call(_ op: String, _ risk: String, _ outcome: String, _ ms: Int, code: String? = nil) -> String {
            "{\n  \"args_sha256\": \"9f2c61a07b8d4e15c3a90b7e2d48f6a1c5e07b93d2f84a6c1e5b07d93a4f8c26\",\n  \"code\": \(code.map { "\"\($0)\"" } ?? "null"),\n  \"ms\": \(ms),\n  \"op\": \"\(op)\",\n  \"outcome\": \"\(outcome)\",\n  \"project\": \"\(project)\",\n  \"risk\": \"\(risk)\",\n  \"session\": \"as_01JC4X7Q3MZ8\"\n}"
        }
        return [
            row(0, "code_mode.call", call("brainAiSearch", "read", "ok", 84)),
            row(1, "code_mode.call", call("connections.jira.create_issue", "risky", "ok", 1_320)),
            row(
                2, "code_mode.call",
                call("connections.jira.create_issue", "risky", "denied", 12, code: "approval_denied")),
            row(3, "code_mode.call", call("brainAiProjectState", "read", "ok", 61)),
            row(4, "brain.ai.proposed", "{\n  \"project\": \"\(project)\",\n  \"room\": \"portal\"\n}"),
            row(5, "code_mode.call", call("brainAiPropose", "write", "ok", 140)),
            row(6, "code_mode.call", call("connections.github.get_issue", "read", "error", 30_002, code: "timeout")),
            row(7, "brain.ai.refused", "{\n  \"project\": \"\(project)\"\n}"),
            row(8, "code_mode.call", call("listAudit", "read", "ok", 47)),
        ]
    }

    nonisolated static func audit(_ count: Int) -> [AuditItem] {
        let kinds: [(String, String, String, String)] = [
            ("pairing.claimed", "pairing", "p_c4e1", "{\n  \"name\": \"iPad Air\",\n  \"platform\": \"ipados\"\n}"),
            ("device.scopes_set", "device", "d_ph18x3Kz", "{\n  \"scopes\": [\n    \"read\",\n    \"approve\"\n  ]\n}"),
            ("setting.set", "setting", "auth.step_up_secs", "{\n  \"new\": 300,\n  \"old\": 120\n}"),
            ("secret.created", "secret", "github-token-test", "{\n  \"delivery\": \"env\",\n  \"size\": 40\n}"),
            ("secret.leased", "secret", "github-token-test", "{\n  \"runner\": \"d_run9Lq1\",\n  \"ttl_secs\": 120\n}"),
            ("auth.lockout_cleared", "lockout", "ip:198.51.100.7", "{}"),
            ("terminal.created", "terminal", "t_91c2", "{\n  \"runner\": \"d_run2Gt4\"\n}"),
            ("connection.used", "connection", "2", "{\n  \"action\": \"github.get_issue\",\n  \"result\": \"ok\"\n}"),
            ("connection.created", "connection", "2", "{\n  \"kind\": \"github\"\n}"),
            ("account.tested", "account", "1", "{\n  \"result\": \"ok\"\n}"),
            ("agent.created", "agent", "as_01JC4X7Q3MZ8N5V2K9R001", "{\n  \"harness\": \"claude\"\n}"),
        ]
        return (0..<count).map { i in
            let k = kinds[(i * 5 + 3) % kinds.count]
            // Mostly people; some rows started by a schedule, Brain or an AI session; the oldest few are from before origins.
            let origin: AuditOrigin? =
                switch i % 7 {
                case 6:
                    AuditOrigin(
                        kind: "schedule", reference: "brain/sync", rootKind: "schedule", rootReference: "brain/sync")
                case 4:
                    AuditOrigin(
                        kind: "ai_session", reference: "as_01JC4X7Q3MZ8", rootKind: "person",
                        rootReference: "d_ph18x3Kz")
                case 2:
                    AuditOrigin(
                        kind: "brain_distil", reference: nil, rootKind: "schedule", rootReference: "brain/distil")
                default:
                    i >= count - 6
                        ? nil
                        : AuditOrigin(
                            kind: "person", reference: "d_ph18x3Kz", rootKind: "person", rootReference: "d_ph18x3Kz")
                }
            return AuditItem(
                seq: Int64(5_230 - i), at: Date().addingTimeInterval(-Double(i) * 1_020 - 300), action: k.0,
                actor: i % 7 == 6 ? .system : .user(1), entityKind: k.1, entityRef: k.2, details: k.3, origin: origin)
        }
    }

    nonisolated static let metricsText = """
        # HELP ainkrad_uptime_seconds Seconds since this process started.
        # TYPE ainkrad_uptime_seconds gauge
        ainkrad_uptime_seconds 367200
        # HELP ainkrad_devices_active Paired, unrevoked devices by kind.
        # TYPE ainkrad_devices_active gauge
        ainkrad_devices_active{kind="app"} 3
        ainkrad_devices_active{kind="runner"} 2
        # HELP ainkrad_runners Runners the hub knows, by state.
        ainkrad_runners{state="connected"} 2
        ainkrad_runners{state="degraded"} 0
        # HELP ainkrad_terminals Terminals by state.
        ainkrad_terminals{state="running"} 2
        # HELP ainkrad_disk_free_percent Free space on the filesystem holding the database.
        ainkrad_disk_free_percent 38
        # HELP ainkrad_db_size_bytes Size of the database file.
        ainkrad_db_size_bytes 18874368
        # HELP ainkrad_backup_age_seconds Age of the newest backup.
        ainkrad_backup_age_seconds 187200
        # HELP ainkrad_certificate_days_left Days until the public certificate expires.
        ainkrad_certificate_days_left 41
        # HELP ainkrad_events_head_seq Newest event sequence.
        ainkrad_events_head_seq 18442
        # HELP ainkrad_alarm_active 1 while the alarm is raised.
        ainkrad_alarm_active{alarm="backup_age"} 1
        ainkrad_alarm_active{alarm="cert_expiry"} 0
        ainkrad_alarm_active{alarm="disk_free"} 0
        """
}
#endif
