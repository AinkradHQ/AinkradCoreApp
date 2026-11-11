import Foundation

/// What `GET /core/health` says, as plain words for the Home widget and the connection pop-up (N9, N14). Anything the Core
/// does not report is nil, and the views say "Not reported yet" for it.
public struct CoreHealthFacts: Equatable, Sendable {
    public var version: String
    public var uptimeSecs: Int64
    public var certDaysLeft: Int?
    public var lastBackupAt: Date?
    public var lastBackupBytes: Int64?

    public init(
        version: String, uptimeSecs: Int64, certDaysLeft: Int? = nil, lastBackupAt: Date? = nil,
        lastBackupBytes: Int64? = nil
    ) {
        self.version = version
        self.uptimeSecs = uptimeSecs
        self.certDaysLeft = certDaysLeft
        self.lastBackupAt = lastBackupAt
        self.lastBackupBytes = lastBackupBytes
    }

    /// "62 days", "1 day", "Expires today", "Expired".
    public var certificate: String? {
        guard let d = certDaysLeft else { return nil }
        switch d {
        case ..<0: return "Expired"
        case 0: return "Expires today"
        case 1: return "1 day"
        default: return "\(d) days"
        }
    }

    /// The bar's share for the certificate: a 90-day certificate is full, nothing left is empty.
    public var certificateShare: Double { min(1, max(0, Double(certDaysLeft ?? 0) / 90)) }
    /// A certificate with under two weeks left needs a look.
    public var certificateLow: Bool { (certDaysLeft ?? 90) < 14 }

    /// "3 hours ago", "Just now"; nil when the Core never made a backup.
    public func backupAge(now: Date) -> String? {
        guard let at = lastBackupAt else { return nil }
        let s = max(0, Int(now.timeIntervalSince(at)))
        switch s {
        case ..<60: return "Just now"
        case ..<3600: return Self.unit(s / 60, "minute") + " ago"
        case ..<86_400: return Self.unit(s / 3600, "hour") + " ago"
        default: return Self.unit(s / 86_400, "day") + " ago"
        }
    }

    /// "3 hours ago, 12 MB", or just the age when the size is not known.
    public func backup(now: Date) -> String? {
        guard let age = backupAge(now: now) else { return nil }
        guard let n = lastBackupBytes else { return age }
        return "\(age), \(ByteCountFormatter.string(fromByteCount: n, countStyle: .file))"
    }

    /// "3 days 4 hours", "2 hours 5 minutes", "40 seconds": the two biggest units.
    public var uptime: String {
        let s = max(0, Int(uptimeSecs))
        let (d, h, m) = (s / 86_400, s % 86_400 / 3600, s % 3600 / 60)
        if d > 0 { return h > 0 ? "\(Self.unit(d, "day")) \(Self.unit(h, "hour"))" : Self.unit(d, "day") }
        if h > 0 { return m > 0 ? "\(Self.unit(h, "hour")) \(Self.unit(m, "minute"))" : Self.unit(h, "hour") }
        if m > 0 { return Self.unit(m, "minute") }
        return Self.unit(s, "second")
    }

    private static func unit(_ n: Int, _ word: String) -> String { n == 1 ? "1 \(word)" : "\(n) \(word)s" }
}
