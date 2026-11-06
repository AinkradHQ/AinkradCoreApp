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
    private(set) var service: (any AdminService)?
    @ObservationIgnored private(set) var registry: RegistryModel!
    @ObservationIgnored private(set) var secrets: SecretsModel!
    @ObservationIgnored private(set) var audit: AuditModel!
    @ObservationIgnored private(set) var ops: OpsModel!

    public init(host: any AdminHost) {
        self.host = host
        registry = RegistryModel(hub: self)
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
        if let f = error as? AdminFailure { return f.message }
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

    /// Adds the five sections to Settings (Core settings, Feature switches, Ops under Core; Secrets and Audit under Security)
    /// and a launcher entry for each. Sections that the shell shipped as placeholders keep their ids.
    public func install() {
        let shell = host.shell
        let list:
            [(id: String, group: SettingsGroup, title: String, symbol: String, order: Int, sub: String, keys: [String])] =
                [
                    (
                        "core", .core, "Core settings", "gearshape", 0, "The settings your Core runs on",
                        ["registry", "limits", "out_of_bounds", "history"]
                    ),
                    (
                        "switches", .core, "Feature switches", "switch.2", 2,
                        "Turn Core features on or off", ["flags", "secrets mode", "passkey", "gates"]
                    ),
                    (
                        "ops", .core, "Ops", "waveform.path.ecg", 3, "How your Core is doing",
                        ["health", "alarms", "metrics", "prometheus"]
                    ),
                    (
                        "secrets", .security, "Secrets", "key", 1, "Keys your runners can be lent",
                        ["broker", "keys", "leases", "tokens"]
                    ),
                    (
                        "audit", .security, "Audit", "doc.text", 2, "Who did what, where and when",
                        ["log", "history", "who did what"]
                    ),
                ]
        for e in list {
            let content: AnyView =
                switch e.id {
                case "core": AnyView(CoreSettingsSection(admin: self))
                case "switches": AnyView(SwitchesSection(admin: self))
                case "ops": AnyView(OpsSection(admin: self))
                case "secrets": AnyView(SecretsSection(admin: self))
                default: AnyView(AuditSection(admin: self))
                }
            shell.settings.section(
                SettingsSection(id: e.id, group: e.group, title: e.title, symbol: e.symbol, order: e.order) { content })
            shell.launcher.register(
                LauncherEntry(
                    id: "admin-\(e.id)", title: e.title, sub: "Settings, \(e.group.rawValue)", symbol: e.symbol,
                    keywords: e.keys
                ) {
                    shell.settings.selected = e.id
                    shell.open(.settings)
                })
        }
    }
}
