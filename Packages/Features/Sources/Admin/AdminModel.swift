import CoreKit
import Foundation
import Observation
import Shell
import SwiftUI

/// The admin area: Core settings with history, Feature switches, Secrets, Audit and Ops. It owns the four section models and
/// the Core service, registers the Settings sections and the launcher entries, and turns a failure into the words each
/// screen shows. The app sets the service once it has a connection.
@MainActor @Observable
public final class AdminModel {
    let host: any AdminHost
    /// Device names by id, when the app knows them (the audit log shows the name, not `d_…`).
    public var deviceNames: [String: String] = [:]
    /// The tab Activity shows: Ops or Audit.
    var activityTab: ActivityTab = .ops
    private(set) var service: (any AdminService)?
    @ObservationIgnored private(set) lazy var registry = RegistryModel(hub: self)
    @ObservationIgnored private(set) var secrets: SecretsModel!
    @ObservationIgnored private(set) var audit: AuditModel!
    @ObservationIgnored private(set) var ops: OpsModel!

    public init(host: any AdminHost) {
        self.host = host
        secrets = SecretsModel(hub: self)
        audit = AuditModel(hub: self)
        ops = OpsModel(hub: self)
    }

    /// The live Core connection: every section loads again.
    public func attach(connection: CoreConnection) { use(LiveAdminService(connection: connection)) }

    func use(_ service: any AdminService) {
        self.service = service
        reloadAll()
    }

    public func detach() {
        service = nil
        registry.reset()
        secrets.reset()
        audit.reset()
        ops.reset()
    }

    public var isConnected: Bool { service != nil }

    func reloadAll() {
        Task { await registry.reload() }
        Task { await secrets.reload() }
        Task { await audit.reload() }
        Task { await ops.reload() }
    }

    /// An event from the Core that may change what these screens show.
    public func event(kind: String) {
        if kind.hasPrefix("setting.") { Task { await registry.reload() } }
        if kind.hasPrefix("secret.") { Task { await secrets.reload() } }
        if kind.hasPrefix("alarm.") { Task { await ops.reload() } }
    }

    /// A gap in the event stream: everything is read again.
    public func resync() { if service != nil { reloadAll() } }

    // MARK: shared by the section models

    /// What a failed read or write means for a section.
    func state(for error: any Error) -> SectionState {
        if let f = error as? AdminFailure {
            return .failed(code: f.code, message: f.message, errorID: f.errorID)
        }
        switch CoreError.unwrapping(error) {
        case .forbiddenScope: return .forbidden
        case .rateLimited(let after):
            host.rateLimited(retryAfter: after)
            return .failed(code: "rate_limited", message: "Too many requests. Nothing was changed.", errorID: nil)
        case .some(.http(_, let code, let message)): return .failed(code: code, message: message, errorID: nil)
        case .some(let e): return .failed(code: Self.code(e), message: e.localizedDescription, errorID: nil)
        case nil: return .failed(code: "unknown", message: error.localizedDescription, errorID: nil)
        }
    }

    /// One line for a refused write, shown in place.
    func words(_ error: any Error) -> String {
        if let f = error as? AdminFailure { return "\(f.message) (\(f.code))" }
        if case .rateLimited(let after)? = CoreError.unwrapping(error) { host.rateLimited(retryAfter: after) }
        return CoreError.unwrapping(error)?.localizedDescription ?? error.localizedDescription
    }

    /// The Core's own code for a refusal, when it sent one.
    func code(_ error: any Error) -> String? {
        if let f = error as? AdminFailure { return f.code }
        return CoreError.unwrapping(error).map(Self.code)
    }

    static func code(_ e: CoreError) -> String {
        switch e {
        case .forbiddenScope: "forbidden_scope"
        case .stepUpRequired: "step_up_required"
        case .rateLimited: "rate_limited"
        case .offline: "offline"
        case .sessionExpired: "session_expired"
        case .http(_, let c, _): c
        case .badRequest: "bad_request"
        default: "error"
        }
    }

    /// Writes are refused while the Core is unreachable or rate limiting: a toast says so. True when the write may go on.
    func mayWrite() -> Bool {
        guard let why = host.pausedReason else { return true }
        host.shell.showToast(why)
        return false
    }

    // MARK: Settings sections and launcher entries

    /// Core settings and Feature switches stay in Settings. Secrets and Activity (Ops, Audit) are apps of their own: each has
    /// a launcher entry that opens its pane. Sections that the shell shipped as placeholders keep their ids.
    public func install() {
        let shell = host.shell
        let list: [(id: String, title: String, symbol: String, order: Int, sub: String, keys: [String])] = [
            (
                "core", "Core settings", "gearshape", 0, "Registry values, their limits and history",
                ["registry", "limits", "out_of_bounds", "history"]
            ),
            (
                "switches", "Feature switches", "switch.2", 2, "Secrets mode, passkey admin, terminal drivers",
                ["flags", "secrets mode", "passkey", "gates"]
            ),
        ]
        for e in list {
            let content: AnyView =
                e.id == "core" ? AnyView(CoreSettingsSection(admin: self)) : AnyView(SwitchesSection(admin: self))
            shell.settings.section(
                SettingsSection(id: e.id, group: .core, title: e.title, symbol: e.symbol, order: e.order) { content })
            shell.launcher.register(
                LauncherEntry(
                    id: "admin-\(e.id)", title: e.title, sub: "Settings, Core", symbol: e.symbol, keywords: e.keys
                ) {
                    shell.settings.selected = e.id
                    shell.open(.settings)
                })
        }
        let apps: [(id: String, title: String, sub: String, symbol: String, keys: [String], run: @MainActor (AdminModel) -> Void)] = [
            (
                "secrets", "Secrets", "Passwords and keys you keep for yourself", "key",
                ["broker", "keys", "leases", "tokens", "password"], { $0.showSecrets() }
            ),
            (
                "activity", "Activity", "How your Core is doing and who did what", "waveform.path.ecg",
                ["ops", "audit", "health", "alarms", "log", "history"], { $0.showActivity() }
            ),
            (
                "admin-ops", "Ops", "Activity, how your Core is doing", "waveform.path.ecg",
                ["health", "alarms", "metrics", "prometheus"], { $0.showActivity(.ops) }
            ),
            (
                "admin-audit", "Audit", "Activity, who did what, where and when", "doc.text",
                ["log", "history", "who did what"], { $0.showActivity(.audit) }
            ),
        ]
        for a in apps {
            shell.launcher.register(
                LauncherEntry(id: a.id, title: a.title, sub: a.sub, symbol: a.symbol, keywords: a.keys) {
                    [weak self] in if let self { a.run(self) }
                })
        }
    }
}
