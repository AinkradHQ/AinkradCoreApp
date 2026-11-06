import CoreUI
import Foundation
import SwiftUI

/// Core settings in plain words: a name, one line of what it does and a group, per key the Core reports. The key and the
/// Core's own description stay as hover help. A key this build doesn't know falls back to its own words.
enum SettingWords {
    struct Group: Identifiable {
        let id: String
        let title: String
        let sub: String
        let symbol: String
        let hue: Color
    }

    static let groups: [Group] = [
        Group(
            id: "sign-in", title: "Sign-in and Touch ID", sub: "How long you stay signed in and unlocked.",
            symbol: "person.badge.key.fill", hue: GlassInk.blue),
        Group(
            id: "requests", title: "Requests", sub: "How much one device may ask of your Core.",
            symbol: "speedometer", hue: GlassInk.blue),
        Group(
            id: "secrets", title: "Secrets", sub: "How many secrets your Core keeps, and how big.",
            symbol: "key.fill", hue: GlassInk.blue),
        Group(
            id: "terminals", title: "Terminals", sub: "How many terminals run, and when idle ones close.",
            symbol: "terminal.fill", hue: GlassInk.blue),
        Group(
            id: "alerts", title: "Warnings", sub: "When your Core warns you about backups, certificates and disk.",
            symbol: "exclamationmark.triangle.fill", hue: GlassInk.orange),
        Group(
            id: "background", title: "Background work", sub: "How often your Core does its routine work.",
            symbol: "gearshape.2.fill", hue: GlassInk.slate),
    ]

    private struct Entry {
        let group: String
        let title: String
        let line: String
        var unit: String?
    }

    private static let entries: [String: Entry] = [
        "auth.step_up_secs": Entry(
            group: "sign-in", title: "Touch ID unlocks for",
            line: "After Touch ID, admin changes stay unlocked this long."),
        "auth.web_session_secs": Entry(
            group: "sign-in", title: "Browser sign-in lasts",
            line: "A browser signed in with a passkey stays signed in this long, then signs in again."),
        "api.requests_per_min": Entry(
            group: "requests", title: "Requests per minute", line: "How many requests one device may send each minute."),
        "api.request_burst": Entry(
            group: "requests", title: "Requests at once",
            line: "How many requests one device may send in a quick burst."),
        "secrets.max_bytes": Entry(
            group: "secrets", title: "Largest secret", line: "The biggest value one secret can hold."),
        "secrets.max_count": Entry(
            group: "secrets", title: "Most secrets", line: "How many secrets your Core keeps at most."),
        "secrets.lease_secs": Entry(
            group: "secrets", title: "A handed-out secret waits",
            line: "How long a runner has to pick up a secret it was given."),
        "secrets.max_leases": Entry(
            group: "secrets", title: "Secrets waiting at once",
            line: "How many handed-out secrets may wait to be picked up at the same time."),
        "terminal.idle_secs": Entry(
            group: "terminals", title: "Unwatched terminals close after",
            line: "A terminal nobody has open closes after this. Never keeps it."),
        "terminal.reap_grace_secs": Entry(
            group: "terminals", title: "Warning before closing",
            line: "After the warning, an unwatched terminal closes this much later unless you open it."),
        "terminal.orphan_grace_secs": Entry(
            group: "terminals", title: "Lost terminals flagged after",
            line: "A terminal a runner still runs but your Core lost track of is flagged after this."),
        "terminal.max_per_device": Entry(
            group: "terminals", title: "Terminals per device", line: "How many terminals one device may have open."),
        "terminal.max_per_runner": Entry(
            group: "terminals", title: "Terminals per runner", line: "How many terminals one runner may run."),
        "terminal.scrollback_bytes": Entry(
            group: "terminals", title: "History per terminal",
            line: "Disk space for one terminal's output history on its runner."),
        "terminal.scrollback_budget_bytes": Entry(
            group: "terminals", title: "History per runner",
            line: "Disk space for all terminal history on one runner. The oldest is freed first."),
        "alarm.backup_max_age_secs": Entry(
            group: "alerts", title: "Backup is too old after", line: "Warn when the newest backup is older than this."),
        "alarm.cert_min_days": Entry(
            group: "alerts", title: "Certificate warning",
            line: "Warn when the certificate has fewer days left than this.",
            unit: "days"),
        "alarm.disk_min_free_pct": Entry(
            group: "alerts", title: "Low disk warning", line: "Warn when free disk space falls below this."),
        "scheduler.tick_secs": Entry(
            group: "background", title: "Routine check every", line: "How often your Core runs its background work."),
        "push.interval_secs": Entry(
            group: "background", title: "Device updates every", line: "How often your Core sends news to your devices."),
        "events.retention_secs": Entry(
            group: "background", title: "Keep history for",
            line: "How long past events can be replayed. Older ones are trimmed."),
        "audit.anchor_interval_secs": Entry(
            group: "background", title: "Audit copy every",
            line: "How often the audit log's fingerprint is saved off this machine, when backups are set up."),
        "secrets.mode": Entry(group: "secrets", title: "Keys and secrets", line: ""),
        "secrets.provider_accounts": Entry(group: "secrets", title: "Real provider keys", line: ""),
        "auth.passkey_admin": Entry(group: "sign-in", title: "Admin from a browser", line: ""),
    ]

    static func title(_ s: SettingItem) -> String {
        entries[s.key]?.title ?? s.name.replacingOccurrences(of: "_", with: " ").capitalizedFirst
    }
    static func line(_ s: SettingItem) -> String { entries[s.key]?.line ?? s.detail }
    /// The plain group this key belongs to; an unknown key gets a group named after its first word.
    static func group(_ s: SettingItem) -> Group {
        if let id = entries[s.key]?.group, let g = groups.first(where: { $0.id == id }) { return g }
        return Group(
            id: s.group, title: s.group.capitalizedFirst, sub: "Settings this app doesn't describe yet.",
            symbol: "slider.horizontal.3", hue: GlassInk.slate)
    }
    /// The Core reads it only when it starts.
    static func needsRestart(_ s: SettingItem) -> Bool { s.detail.contains("read at start") }

    /// A value the way people say it: `5 min`, `8 h`, `30 days`, `8 MB`, `10%`, `1,200 a minute`.
    static func value(_ s: SettingItem, _ n: Int64) -> String {
        if s.key == "secrets.mode" {
            return ["Off", "Test keys", "Real keys"].indices.contains(Int(n))
                ? ["Off", "Test keys", "Real keys"][Int(n)] : "\(n)"
        }
        if RegistryModel.switchKeys.contains(s.key) { return n == 0 ? "Off" : "On" }
        return switch entries[s.key]?.unit ?? s.unit {
        case "seconds": duration(n, zero: s.min == 0 ? "Never" : "0 s")
        case "bytes": ByteCountFormatter.string(fromByteCount: n, countStyle: .binary)
        case "percent": "\(n)%"
        case "per_minute": "\(n.formatted()) a minute"
        case "days": n == 1 ? "1 day" : "\(n) days"
        case "count": n.formatted()
        default: "\(n) \(s.unit)"
        }
    }

    static func duration(_ n: Int64, zero: String = "0 s") -> String {
        if n == 0 { return zero }
        let units: [(Int64, String, String)] = [
            (31_536_000, "year", "years"), (86_400, "day", "days"), (3_600, "h", "h"), (60, "min", "min"),
        ]
        for (size, one, many) in units where n >= size && n % size == 0 {
            let k = n / size
            return "\(k) \(k == 1 ? one : many)"
        }
        if n >= 3_600 { return "\(n / 3_600) h \((n % 3_600) / 60) min" }
        if n >= 60 { return "\(n / 60) min \(n % 60) s" }
        return "\(n) s"
    }
}

extension String {
    fileprivate var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
